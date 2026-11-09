import Foundation

/// Where the app and its extensions keep the dictionaries and settings.
///
/// The share panel can only read the dictionaries if both live in an App
/// Group container. Sideloading tools may rename the group, so besides our
/// own identifier we also try whatever groups the provisioning profile grants.
enum SharedStorage {
    static let preferredGroup = "group.com.nixosm.kotoba"

    /// The App Group in use, or nil when the install doesn't have one.
    static let groupID: String? = {
        let candidates = [preferredGroup] + profileGroups()
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    static var groupContainer: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    /// The app's private Application Support folder (where older versions kept everything).
    static var privateFolder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Shared settings; falls back to the app's own defaults without a group.
    static let defaults: UserDefaults = groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard

    static let databaseName = "dictionaries.sqlite"

    /// The folder that holds the database and added fonts: shared when possible.
    static var folder: URL {
        if let shared = groupContainer?.appendingPathComponent("Library/Application Support", isDirectory: true) {
            try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            return shared
        }
        return privateFolder
    }

    /// True when an extension can see the dictionaries.
    static var databaseIsShared: Bool {
        guard groupContainer != nil else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(databaseName).path)
    }

    /// App only, before opening the database: moves the dictionaries (and
    /// fonts) from the private folder into the shared one. Same disk, so even
    /// gigabytes move instantly. Returns the folder to use.
    static func migrateToSharedFolder() -> URL {
        guard groupContainer != nil else { return privateFolder }
        let fm = FileManager.default
        let from = privateFolder, to = folder
        let oldDB = from.appendingPathComponent(databaseName)
        if fm.fileExists(atPath: oldDB.path), !fm.fileExists(atPath: to.appendingPathComponent(databaseName).path) {
            do {
                for suffix in ["", "-wal", "-shm"] {
                    let file = from.appendingPathComponent(databaseName + suffix)
                    if fm.fileExists(atPath: file.path) {
                        try fm.moveItem(at: file, to: to.appendingPathComponent(databaseName + suffix))
                    }
                }
            } catch {
                // Put back whatever moved and keep using the private copy.
                for suffix in ["", "-wal", "-shm"] {
                    let moved = to.appendingPathComponent(databaseName + suffix)
                    if fm.fileExists(atPath: moved.path) {
                        try? fm.moveItem(at: moved, to: from.appendingPathComponent(databaseName + suffix))
                    }
                }
                return from
            }
        }
        let oldFonts = from.appendingPathComponent("Fonts", isDirectory: true)
        let newFonts = to.appendingPathComponent("Fonts", isDirectory: true)
        if fm.fileExists(atPath: oldFonts.path), !fm.fileExists(atPath: newFonts.path) {
            try? fm.moveItem(at: oldFonts, to: newFonts)
        }
        return fm.fileExists(atPath: oldDB.path) ? from : to
    }

    /// App Groups listed in this bundle's embedded.mobileprovision.
    private static func profileGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups.filter { !$0.contains("*") }
    }
}
