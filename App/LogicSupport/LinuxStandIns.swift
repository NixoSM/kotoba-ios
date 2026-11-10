import Foundation

// Stand-ins for the two pieces of the app that need an iPhone, so the rest of
// its logic (search, the results page, settings) compiles and is tested on
// Linux by the package at the root of the repository. Never part of the app.

/// The app keeps its files in an App Group folder; the tests use a scratch folder.
enum SharedStorage {
    nonisolated(unsafe) static var folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kotoba-logic-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    nonisolated(unsafe) static var defaults: UserDefaults = UserDefaults(suiteName: "kotoba-logic-tests-\(UUID().uuidString)") ?? .standard

    static let databaseName = "dictionaries.sqlite"
}
