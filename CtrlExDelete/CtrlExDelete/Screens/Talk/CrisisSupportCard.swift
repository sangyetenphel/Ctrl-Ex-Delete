import SwiftUI

/// Crisis resources shown right under Ced's reply when a message suggests
/// self-harm or danger. Nothing opens by itself: calling, texting and the
/// support sheet only happen when the user taps.
///
/// `tel:` and `sms:` links open the Phone and Messages apps on an iPhone
/// (the Simulator can't place calls or send texts).
struct CrisisSupportCard: View {
    let support: CrisisSupport
    /// Opens the existing "Connect with human support" sheet.
    let onMoreSupport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(support == .danger ? "Your safety comes first" : "You don\u{2019}t have to carry this alone")
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.foreground)

            if support == .danger {
                callLink("Call 911", url: "tel:911", filled: true)
                    .accessibilityHint("Calls emergency services")
            }

            HStack(spacing: 8) {
                callLink("Call 988", url: "tel:988", filled: support == .crisis)
                    .accessibilityHint("Calls the 988 Suicide and Crisis Lifeline")
                callLink("Text 988", url: "sms:988", filled: false)
                    .accessibilityHint("Opens Messages to text the 988 Lifeline")
            }

            Text(support == .danger
                 ? "988 is free and confidential, 24/7."
                 : "988 is free and confidential, 24/7. In immediate danger? Call 911.")
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            Button("More ways to get support", action: onMoreSupport)
                .cedTextStyle(.captionBold)
                .foregroundStyle(CEDColor.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(CEDColor.rose.opacity(0.5), lineWidth: 1.5))
        .padding(.leading, 34) // lines up with Ced's bubbles (avatar + spacing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crisis support")
    }

    private func callLink(_ title: String, url: String, filled: Bool) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title)
                .cedTextStyle(.bodyBold)
                .foregroundStyle(filled ? CEDColor.cream : CEDColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(filled ? CEDColor.primary : CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: CEDRadius.lg).strokeBorder(CEDColor.primary, lineWidth: 1.5))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    VStack(spacing: 20) {
        CrisisSupportCard(support: .crisis) {}
        CrisisSupportCard(support: .danger) {}
    }
    .padding()
    .background(CEDColor.background)
}
