public struct UTType: Hashable, Sendable {
    public var identifier: String
    public static let zip = UTType(identifier: "public.zip-archive")
    public static let json = UTType(identifier: "public.json")
    public static let plainText = UTType(identifier: "public.plain-text")
}
