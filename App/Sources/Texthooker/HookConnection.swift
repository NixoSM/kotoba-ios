import Foundation
import Network
import KotobaCore

/// The address of the PC's texthooker WebSocket, as typed: "192.168.1.20",
/// "192.168.1.20:6677", "ws://desktop.local:6677"…
struct HookAddress: Equatable {
    var host: String
    var port: UInt16

    static let defaultPort: UInt16 = 6677

    init?(_ typed: String, defaultPort: UInt16 = HookAddress.defaultPort) {
        var t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["ws://", "wss://", "http://", "https://"] where t.lowercased().hasPrefix(scheme) {
            t.removeFirst(scheme.count)
        }
        if let slash = t.firstIndex(of: "/") { t = String(t[..<slash]) }
        guard !t.isEmpty else { return nil }
        var port = defaultPort
        if t.hasPrefix("[") {
            // [IPv6]:port
            guard let close = t.firstIndex(of: "]") else { return nil }
            let rest = t[t.index(after: close)...]
            if rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) { port = p }
            t = String(t[t.index(after: t.startIndex)..<close])
        } else if t.filter({ $0 == ":" }).count == 1, let colon = t.firstIndex(of: ":") {
            guard let p = UInt16(t[t.index(after: colon)...]) else { return nil }
            port = p
            t = String(t[..<colon])
        }
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        host = t
        self.port = port
    }

    var url: URL? {
        let h = host.contains(":") ? "[\(host)]" : host
        return URL(string: "ws://\(h):\(port)")
    }
}

/// Keeps a WebSocket open to the PC and hands over every line that arrives.
/// The Textractor extension only opens its server after the first line it
/// hooks, and Wi-Fi comes and goes, so it simply keeps trying.
@MainActor
final class HookSocket {
    enum State: Equatable {
        case off
        case connecting
        case connected
        /// Waiting before the next try, with why the last one failed.
        case retrying(Problem)
    }

    enum Problem: Equatable {
        /// The PC answered, but nothing listens on that port yet.
        case refused
        /// No answer: wrong address, another Wi-Fi, or the Windows firewall.
        case unreachable
        /// iOS blocked it: Local Network permission is off.
        case permission
        case closed
        case other(String)
    }

    var onState: (State) -> Void = { _ in }
    var onText: (String) -> Void = { _ in }

    private(set) var state = State.off { didSet { if state != oldValue { onState(state) } } }
    private var connection: NWConnection?
    private var address: HookAddress?
    private var retry: Task<Void, Never>?
    private var failures = 0
    /// Callbacks from a connection already replaced are ignored.
    private var generation = 0

    func start(_ address: HookAddress) {
        if self.address == address, state != .off { return }
        stop()
        self.address = address
        failures = 0
        connect()
    }

    func stop() {
        generation += 1
        retry?.cancel()
        retry = nil
        connection?.cancel()
        connection = nil
        address = nil
        state = .off
    }

    /// Try again now (the person tapped the status, or the app came back).
    func reconnect() {
        guard let address else { return }
        generation += 1
        retry?.cancel()
        connection?.cancel()
        connection = nil
        self.address = address
        failures = 0
        connect()
    }

    private func connect() {
        guard let address, let url = address.url else { return }
        generation += 1
        let current = generation
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 4
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        let parameters = NWParameters(tls: nil, tcp: tcp)
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 1 << 20
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        let connection = NWConnection(to: .url(url), using: parameters)
        self.connection = connection
        state = .connecting
        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            MainActor.assumeIsolated {
                guard let self, let connection, self.generation == current else { return }
                switch newState {
                case .ready:
                    self.failures = 0
                    self.state = .connected
                    self.receive(on: connection, generation: current)
                case .waiting(let error), .failed(let error):
                    self.fail(Self.problem(error))
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func receive(on connection: NWConnection, generation current: Int) {
        connection.receiveMessage { [weak self, weak connection] data, context, _, error in
            MainActor.assumeIsolated {
                guard let self, let connection, self.generation == current else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                if metadata?.opcode == .close {
                    self.fail(.closed)
                    return
                }
                if let data, !data.isEmpty, metadata?.opcode == .text || metadata?.opcode == .binary {
                    self.onText(String(decoding: data, as: UTF8.self))
                }
                if let error {
                    self.fail(Self.problem(error))
                    return
                }
                self.receive(on: connection, generation: current)
            }
        }
    }

    private func fail(_ problem: Problem) {
        generation += 1
        connection?.cancel()
        connection = nil
        failures += 1
        state = .retrying(problem)
        // 1, 2, 3, 3, 3… seconds: Textractor may start its server any moment.
        let delay = min(3, failures)
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    nonisolated static func problem(_ error: NWError) -> Problem {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED, .ECONNRESET: return .refused
            case .ETIMEDOUT, .EHOSTUNREACH, .EHOSTDOWN: return .unreachable
            case .ENETDOWN, .ENETUNREACH: return .permission
            case .ECANCELED: return .closed
            default: return .other(error.localizedDescription)
            }
        case .dns(let code):
            // kDNSServiceErr_PolicyDenied: Local Network permission refused.
            return code == -65570 ? .permission : .unreachable
        default:
            return .other(error.localizedDescription)
        }
    }
}

/// Looks for a texthooker on the Wi-Fi: tries the port on every address of
/// the phone's /24 network, so nobody has to type `ipconfig`.
enum HookFinder {
    static func find(port: UInt16 = HookAddress.defaultPort) async -> String? {
        guard let own = LocalAddress.wifiIPv4() else { return nil }
        let parts = own.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."
        let hosts = (1...254).filter { $0 != Int(parts[3]) }.map { prefix + String($0) }
        // In batches, so iOS isn't asked for 250 sockets at once.
        for batch in stride(from: 0, to: hosts.count, by: 64).map({ Array(hosts[$0..<min($0 + 64, hosts.count)]) }) {
            let found: String? = await withTaskGroup(of: String?.self, returning: String?.self) { group in
                for host in batch { group.addTask { await isOpen(host: host, port: port) ? host : nil } }
                for await result in group { if let result { group.cancelAll(); return result } }
                return nil
            }
            if let found { return found }
            if Task.isCancelled { return nil }
        }
        return nil
    }

    /// Whether a TCP connection opens within a second.
    static func isOpen(host: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 1
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: NWParameters(tls: nil, tcp: tcp))
        let queue = DispatchQueue(label: "kotoba.finder")
        return await withCheckedContinuation { continuation in
            let once = Once()
            func finish(_ value: Bool) {
                guard once.take() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1.5) { finish(false) }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func take() -> Bool { lock.withLock { defer { done = true }; return !done } }
    }
}

enum LocalAddress {
    /// The phone's IPv4 address on Wi-Fi (en0), e.g. 192.168.1.34.
    static func wifiIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found = String(cString: host)
                break
            }
        }
        return found
    }
}

/// The other way round, for when the WebSocket can't get through: the phone
/// listens and the PC sends. A small script copies each line Textractor puts
/// on the clipboard to http://<phone>:6678, and the same address opened in a
/// browser on the PC shows a box to paste lines into by hand.
@MainActor
final class HookInbox {
    static let port: UInt16 = 6678

    enum State: Equatable { case off, listening, failed(String) }

    var onState: (State) -> Void = { _ in }
    var onText: (String) -> Void = { _ in }
    private(set) var state = State.off { didSet { if state != oldValue { onState(state) } } }
    private var listener: NWListener?

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.stateUpdateHandler = { [weak self] newState in
                MainActor.assumeIsolated {
                    guard let self, self.listener === listener else { return }
                    switch newState {
                    case .ready: self.state = .listening
                    case .failed(let error):
                        self.state = .failed(error.localizedDescription)
                        self.listener?.cancel()
                        self.listener = nil
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.serve(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .off
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, buffer: Data())
        // Nobody keeps the phone's door open: drop slow clients.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { connection.cancel() }
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch MiniHTTP.parse(buffer) {
                case .done(let request):
                    self.answer(request, on: connection)
                case .bad:
                    self.send(MiniHTTP.response(status: "400 Bad Request"), on: connection)
                case .needMore:
                    if isComplete || error != nil { connection.cancel() } else { self.read(connection, buffer: buffer) }
                }
            }
        }
    }

    private func answer(_ request: MiniHTTP.Request, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            send(MiniHTTP.response(status: "204 No Content"), on: connection)
        case ("POST", _):
            let text = String(decoding: request.body, as: UTF8.self)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onText(text) }
            send(MiniHTTP.response(status: "200 OK", body: Data("ok".utf8)), on: connection)
        case ("GET", _):
            send(MiniHTTP.response(status: "200 OK", type: "text/html; charset=utf-8", body: Data(Self.page.utf8)), on: connection)
        default:
            send(MiniHTTP.response(status: "405 Method Not Allowed"), on: connection)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// The page a browser on the PC gets: paste a line, it appears on the phone.
    static var page: String {
        """
        <!doctype html><html lang="\(L10n.htmlLang)"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>Kotoba</title>
        <style>
        body{font:16px system-ui,sans-serif;background:#f4efe6;color:#2a2420;max-width:40em;margin:3em auto;padding:0 1em}
        textarea{width:100%;height:7em;font-size:20px;padding:.5em;border:1px solid #c9bfae;border-radius:6px;background:#fffdf8}
        button{margin-top:.6em;font-size:16px;padding:.5em 1.4em;border:0;border-radius:6px;background:#c8452e;color:#fff}
        #s{color:#7a6f63;margin-left:1em}
        </style>
        <h1>言葉 Kotoba</h1>
        <p>\(tr("Incolla una riga e premi Invio: appare sull'iPhone."))</p>
        <textarea id="t" autofocus></textarea><br><button id="b">\(tr("Invia"))</button><span id="s"></span>
        <script>
        const t=document.getElementById('t'),s=document.getElementById('s');
        async function go(){const v=t.value.trim();if(!v)return;
        try{await fetch('/text',{method:'POST',headers:{'Content-Type':'text/plain; charset=utf-8'},body:v});t.value='';s.textContent='✓'}
        catch(e){s.textContent='✗'}}
        document.getElementById('b').onclick=go;
        t.onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();go()}};
        </script></html>
        """
    }
}
