import SwiftUI

/// "This chapter belongs to you.": the closing screen with Ced and the
/// keepsake options.
struct FinalGiftView: View {
    @State private var isKeepsakeSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    GhostView(size: 90)
                    HStack(spacing: 8) {
                        ForEach(["\u{1F338}", "\u{2728}", "\u{1F33F}"], id: \.self) { emoji in
                            Text(emoji).font(.system(size: 24))
                        }
                    }
                    .accessibilityHidden(true)
                }

                VStack(spacing: 12) {
                    Text("This chapter belongs to you.")
                        .cedTextStyle(.finalTitle)
                        .foregroundStyle(CEDColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text("These memories are not about the relationship you lost. They are about the person you became while finding your way back to yourself.")
                        .cedTextStyle(.bodyRelaxed)
                        .foregroundStyle(CEDColor.mutedForeground)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    // Like the prototype, this only changes the button for now;
                    // no file is created yet.
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { isKeepsakeSaved = true }
                    } label: {
                        HStack(spacing: 8) {
                            CEDIconView(icon: .download, size: 20, color: CEDColor.cream)
                            Text(isKeepsakeSaved ? "Scrapbook saved \u{2713}" : "Download as keepsake")
                        }
                        .cedTextStyle(.button)
                        .foregroundStyle(CEDColor.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            isKeepsakeSaved ? Color(hex: 0x6BA84A) : CEDColor.primary,
                            in: RoundedRectangle(cornerRadius: CEDRadius.xl)
                        )
                    }
                    .buttonStyle(PressScaleButtonStyle())

                    // These two have no action in the prototype yet.
                    OutlineButton(title: "Keep the app \u{B7} continue growing") {}
                    OutlineButton(title: "Close chapter \u{B7} archive room",
                                  color: CEDColor.mutedForeground,
                                  borderColor: CEDColor.border) {}
                }

                Text("Your data stays private. Nothing is shared without your permission.")
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.hint)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(CEDColor.background)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    FinalGiftView()
}
