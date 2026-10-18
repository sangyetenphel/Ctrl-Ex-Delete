import AVFoundation

/// What tapping "Take Photo" should do, given the device and its camera permission.
/// Kept separate from the screen so the decision is easy to read and test.
enum CameraRoute: Equatable {
    /// Permission already given: open the camera.
    case open
    /// First time: ask for permission, then open the camera if allowed.
    case askPermission
    /// Turned off in Settings (or blocked by Screen Time): explain how to allow it.
    case denied
    /// No camera on this device (for example the Simulator): use the photo library.
    case unavailable

    static func route(isCameraAvailable: Bool, status: AVAuthorizationStatus) -> CameraRoute {
        guard isCameraAvailable else { return .unavailable }
        switch status {
        case .authorized: return .open
        case .notDetermined: return .askPermission
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}
