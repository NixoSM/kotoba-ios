"""Checks the extension's server on Linux: build it with -DKOTOBA_TEST, run this.

    gcc -DKOTOBA_TEST -O1 -o test_server kotoba_websocket.c -lpthread
    python3 test_extension.py ./test_server
"""
import base64, hashlib, os, socket, struct, subprocess, sys, time, json

def connect(path):
    for _ in range(50):
        try:
            s = socket.create_connection(("127.0.0.1", 6677), timeout=2)
            break
        except OSError:
            time.sleep(0.1)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(f"GET {path} HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
              f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(4096)
    head, rest = buf.split(b"\r\n\r\n", 1)
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    assert b"101" in head and accept in head.decode(), head
    return s, rest

def frames(s, buf, wait=0.6):
    out, end = [], time.time() + wait
    s.settimeout(0.05)
    while time.time() < end:
        try:
            data = s.recv(65536)
            if not data:
                break
            buf += data
        except socket.timeout:
            pass
        while len(buf) >= 2:
            op, n, h = buf[0] & 15, buf[1] & 127, 2
            if n == 126: n, h = struct.unpack(">H", buf[2:4])[0], 4
            elif n == 127: n, h = struct.unpack(">Q", buf[2:10])[0], 10
            if len(buf) < h + n:
                break
            out.append((op, buf[h:h + n])); buf = buf[h + n:]
    return out

def texts(fs):
    return [p.decode() for op, p in fs if op == 1]

def masked(s, op, payload=b""):
    m = os.urandom(4)
    s.sendall(bytes([0x80 | op, 0x80 | len(payload)]) + m + bytes(b ^ m[i % 4] for i, b in enumerate(payload)))

server = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
session = server.stdout.readline().split()[1]
def say(line):
    server.stdin.write(line + "\n"); server.stdin.flush()

plain, rest = connect("/")              # texthooker-ui style
say("一行目「こんにちは」"); say('引用 " と \\'); time.sleep(0.3)
assert texts(frames(plain, rest)) == ["一行目「こんにちは」", '引用 " と \\'], "plain clients get new lines as text"

k, rest = connect(f"/?kotoba=1&session={session}&since=1")
got = [json.loads(t) for t in texts(frames(k, rest))]
assert [g["sentence"] for g in got] == ['引用 " と \\'] and got[0]["id"] == 2 and got[0]["session"] == session, got

k2, rest = connect("/?kotoba=1&session=other&since=99")
assert [json.loads(t)["id"] for t in texts(frames(k2, rest))] == [1, 2], "a new Textractor run sends everything"

masked(k, 9, b"hi")
assert (10, b"hi") in frames(k, b""), "ping gets a pong"
say("三行目"); time.sleep(0.2)
assert [json.loads(t)["sentence"] for t in texts(frames(k, b""))] == ["三行目"]
masked(k, 8, b"\x03\xe8")
assert any(op == 8 for op, _ in frames(k, b"")), "close is answered"

server.stdin.close(); server.wait(timeout=5)
print("extension server: OK")
