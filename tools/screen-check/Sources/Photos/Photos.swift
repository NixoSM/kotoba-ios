public enum PHAuthorizationStatus: Sendable { case notDetermined, restricted, denied, authorized, limited }
public enum PHAccessLevel: Sendable { case addOnly, readWrite }
public enum PHPhotoLibrary {
    public static func requestAuthorization(for level: PHAccessLevel, handler: @escaping @Sendable (PHAuthorizationStatus) -> Void) {}
    public static func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus { .denied }
}
