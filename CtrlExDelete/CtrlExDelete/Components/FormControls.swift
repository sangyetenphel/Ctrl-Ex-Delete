import SwiftUI

/// A selectable answer button (e.g. "Not really / A little / A lot"):
/// powder blue with a dark blue border when chosen, white otherwise.
struct OptionButton: View {
    let title: String
    let isSelected: Bool
    var verticalPadding: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .cedTextStyle(.bodySemibold)
                .foregroundStyle(isSelected ? CEDColor.primary : CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, verticalPadding)
                .selectableBackground(isSelected: isSelected, cornerRadius: CEDRadius.lg)
        }
        .buttonStyle(.plain)
    }
}

/// A multi-line text box in the prototype's `<textarea>` style.
struct CEDTextArea: View {
    @Binding var text: String
    var placeholder = ""
    /// How many lines tall the box is before it starts scrolling.
    var lines = 3
    var background = CEDColor.card

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(CEDColor.foreground.opacity(0.5)),
            axis: .vertical
        )
        .lineLimit(lines, reservesSpace: true)
        .cedTextStyle(.body)
        .foregroundStyle(CEDColor.foreground)
        .tint(CEDColor.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(background, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(CEDColor.border, lineWidth: 1))
    }
}

extension View {
    /// The white header strip used at the top of most screens, with a thin
    /// line underneath. Its white runs up behind the status bar.
    func cardHeaderStyle(bottomPadding: CGFloat = 20) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, bottomPadding)
            .background(CEDColor.card.ignoresSafeArea(edges: .top))
            .overlay(alignment: .bottom) {
                Rectangle().fill(CEDColor.border).frame(height: 1)
            }
    }

    /// Paints the area behind the status bar. Used on screens whose header
    /// scrolls with the page, so the header's color can't reach up there itself.
    func statusBarBackground(_ color: Color) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(color, ignoresSafeAreaEdges: .top)
        }
    }

    /// The bold 14pt question label used above answer options.
    func questionLabelStyle() -> some View {
        self
            .cedTextStyle(.bodyBold)
            .foregroundStyle(CEDColor.foreground)
    }
}

/// A round 40pt badge with an icon or artwork inside (used at the top of
/// the reflection, talk and moving-forward screens).
struct IconBadge<Content: View>: View {
    var size: CGFloat = 40
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(CEDColor.secondary, in: Circle())
    }
}
