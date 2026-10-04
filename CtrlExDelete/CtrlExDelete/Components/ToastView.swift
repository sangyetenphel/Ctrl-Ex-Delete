import SwiftUI

/// A small dark pill message that floats near the bottom of a screen,
/// like the prototype's "Saved for another day" notification.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .cedTextStyle(.toast)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(CEDColor.foreground, in: Capsule())
            .allowsHitTesting(false)
    }
}
