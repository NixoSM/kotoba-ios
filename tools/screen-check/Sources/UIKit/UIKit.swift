@_exported import Foundation
@_exported import SwiftUI

@MainActor public final class UIPasteboard {
    public static let general = UIPasteboard()
    public var string: String?
    public var hasStrings: Bool { string != nil }
    public var changeCount: Int { 0 }
}
