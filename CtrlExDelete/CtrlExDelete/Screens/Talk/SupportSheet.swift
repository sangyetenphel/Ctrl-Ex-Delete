import SwiftUI

/// "Connect with human support": a bottom sheet with the 988 crisis line.
/// Opened from "Get human support" in the chat with Ced.
struct SupportSheet: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed backdrop; tapping it closes the sheet.
            Color(hex: 0x2D4052, opacity: 0.4)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityLabel("Close human support")
                .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(CEDColor.border)
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                    .accessibilityHidden(true)

                Text("Connect with human support")
                    .cedTextStyle(.sheetTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)

                Text("In the U.S., 988 offers free, confidential support for emotional distress, 24/7.")
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .padding(.bottom, 20)

                VStack(spacing: 12) {
                    supportLink("Call 988", url: "tel:988",
                                text: CEDColor.cream, fill: CEDColor.primary, border: CEDColor.primary)
                    supportLink("Text 988", url: "sms:988",
                                text: CEDColor.primary, fill: CEDColor.card, border: CEDColor.primary)
                    supportLink("Chat with 988", url: "https://988lifeline.org/chat/",
                                text: CEDColor.foreground, fill: CEDColor.card, border: CEDColor.border)
                }

                Text("For immediate danger or a medical emergency, call 911.")
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                    .fill(CEDColor.card)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .accessibilityAction(.escape) { close() }
    }

    private func supportLink(_ title: String, url: String, text: Color, fill: Color, border: Color) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title)
                .cedTextStyle(.bodyBold)
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
                .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(border, lineWidth: 2))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.25)) {
            router.isSupportSheetPresented = false
        }
    }
}
