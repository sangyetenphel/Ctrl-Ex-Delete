import SwiftUI

/// After "I'll try this": a short reflection that becomes a scrapbook memory
/// for the selected activity.
struct ReflectionView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey

    @State private var note = ""
    @State private var thoughtAboutEx: String?
    @State private var moodComparison: String?
    @State private var noticed = ""

    private let thoughtOptions = ["Not really", "A little", "A lot"]
    private let moodOptions = ["Worse", "About the same", "A little better", "Much better"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    photoPlaceholder

                    VStack(alignment: .leading, spacing: 8) {
                        Text("A short note about today").questionLabelStyle()
                        CEDTextArea(text: $note, placeholder: "I felt calmer once I went outside\u{2026}", lines: 3)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Did you think about your ex during the activity?").questionLabelStyle()
                        HStack(spacing: 8) {
                            ForEach(thoughtOptions, id: \.self) { option in
                                OptionButton(title: option, isSelected: thoughtAboutEx == option, verticalPadding: 10) {
                                    thoughtAboutEx = option
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How do you feel now compared to before?").questionLabelStyle()
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                moodButton(moodOptions[0])
                                moodButton(moodOptions[1])
                            }
                            GridRow {
                                moodButton(moodOptions[2])
                                moodButton(moodOptions[3])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you notice?").questionLabelStyle()
                        CEDTextArea(text: $noticed, placeholder: "I felt calmer once I went outside\u{2026}", lines: 2)
                    }

                    PrimaryButton(title: "Add to my scrapbook") {
                        journey.addMemory(note: note.isEmpty ? noticed : note)
                        router.go(to: .scrapbook)
                    }
                    .padding(.bottom, 8)
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(CEDColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconBadge {
                CEDIconView(icon: .check, size: 20, color: CEDColor.primary)
            }
            .padding(.bottom, 12)

            Text("You showed up.")
                .cedTextStyle(.pageTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("Add a small piece of today to your scrapbook.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 4)
        }
        .cardHeaderStyle()
    }

    /// The prototype's dashed photo box. Adding a photo isn't built yet,
    /// so (like the prototype) it is a placeholder only.
    private var photoPlaceholder: some View {
        VStack(spacing: 8) {
            CEDIconView(icon: .image, size: 32, color: CEDColor.mutedForeground)
            Text("Add a photo")
                .cedTextStyle(.bodySemibold)
                .foregroundStyle(CEDColor.mutedForeground)
            Text("or continue without one")
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.hint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 144)
        .background(CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CEDRadius.xl)
                .strokeBorder(CEDColor.border, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .accessibilityElement(children: .combine)
    }

    private func moodButton(_ option: String) -> some View {
        OptionButton(title: option, isSelected: moodComparison == option) {
            moodComparison = option
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ReflectionView()
        .environment(AppRouter(start: .reflection))
        .environment(JourneyStore())
}
