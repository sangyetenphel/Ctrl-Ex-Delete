import SwiftUI

/// Shrinks a button slightly while it is pressed (the prototype's `active:scale-95`).
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The large rounded call-to-action button used at the bottom of screens.
struct PrimaryButton: View {
    let title: String
    var isEnabled = true
    var enabledTextColor = CEDColor.cream
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .cedTextStyle(.button)
                .foregroundStyle(isEnabled ? enabledTextColor : CEDColor.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    isEnabled ? CEDColor.primary : CEDColor.border,
                    in: RoundedRectangle(cornerRadius: CEDRadius.xl)
                )
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: isEnabled)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!isEnabled)
    }
}

/// Colors for any option the user can select (cards, energy buttons, chips):
/// powder blue with a dark blue border when selected, white otherwise.
struct SelectableBackground: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(isSelected ? CEDColor.secondary : CEDColor.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? CEDColor.primary : CEDColor.border, lineWidth: 2))
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    func selectableBackground(isSelected: Bool, cornerRadius: CGFloat) -> some View {
        modifier(SelectableBackground(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}
