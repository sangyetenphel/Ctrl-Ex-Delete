import SwiftUI

/// "Your Journey": a celebration, recent memories, a button to add a memory
/// and a timeline of milestones.
struct ScrapbookView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey

    private var completed: Int { journey.summary?.activitiesCompleted ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 20) {
                    if completed > 0 {
                        celebrationCard
                    }
                    recentMemories
                    captureButton
                    timeline

                    Button("View your insights \u{2192}") {
                        router.go(to: .progress)
                    }
                    .cedTextStyle(.bodySemibold)
                    .foregroundStyle(CEDColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .statusBarBackground(CEDColor.card)
        .background(CEDColor.background)
        // Photo links expire after an hour, so fetch fresh ones each visit.
        .task { await journey.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Journey")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow)
                .foregroundStyle(CEDColor.primary)
                .padding(.bottom, 4)

            Text("Look how far you\u{2019}ve come.")
                .cedTextStyle(.screenTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("\(completed) \(completed == 1 ? "activity" : "activities") explored \u{B7} \(journey.memories.count) \(journey.memories.count == 1 ? "memory" : "memories") collected")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 8)
        }
        .cardHeaderStyle()
    }

    private var celebrationCard: some View {
        HStack(spacing: 12) {
            IconBadge {
                CEDIconView(icon: .star, size: 18, color: CEDColor.primary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("A moment to celebrate")
                    .textCase(.uppercase)
                    .cedTextStyle(.captionBold.tracking(0.6))
                    .foregroundStyle(CEDColor.mutedForeground)
                Text("You\u{2019}ve made time for yourself \(completed == 1 ? "once" : "\(completed) times").")
                    .cedTextStyle(.bodySemibold)
                    .foregroundStyle(CEDColor.foreground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: 0xFFF3CC), in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .accessibilityElement(children: .combine)
    }

    private var recentMemories: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Memories")
                .cedTextStyle(.sectionTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            if journey.memories.isEmpty {
                Text(memoriesPlaceholder)
                    .cedTextStyle(.body)
                    .foregroundStyle(CEDColor.mutedForeground)
            }

            // Two cards per row; cards in the same row share the same height.
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(stride(from: 0, to: journey.memories.count, by: 2)), id: \.self) { start in
                    GridRow {
                        MemoryCard(memory: journey.memories[start])
                        if start + 1 < journey.memories.count {
                            MemoryCard(memory: journey.memories[start + 1])
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    private var memoriesPlaceholder: String {
        if !journey.hasLoaded { return "Loading your memories\u{2026}" }
        if let error = journey.loadError { return "Your memories couldn\u{2019}t be loaded. \(error)" }
        return "Your memories will show up here after your first reflection."
    }

    private var captureButton: some View {
        VStack(spacing: 8) {
            // Opens the reflection for the activity chosen with "I'll try this"
            // (or a memory without one, if nothing is chosen).
            PrimaryButton(title: "+ Capture an activity") {
                router.go(to: .reflection)
            }
            Text("Add a photo and reflection from an activity you completed.")
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your story so far")
                .cedTextStyle(.sectionTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                let milestones = journey.milestones
                ForEach(milestones.indices, id: \.self) { index in
                    let item = milestones[index]
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(item.isDone ? CEDColor.primary : CEDColor.border)
                                .frame(width: 12, height: 12)
                                .padding(.top, 4)
                            if index < milestones.count - 1 {
                                Rectangle()
                                    .fill(item.isDone ? CEDColor.rose : CEDColor.border)
                                    .frame(width: 2, height: 24)
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.label)
                                .cedTextStyle(.bodySemibold)
                                .foregroundStyle(item.isDone ? CEDColor.foreground : CEDColor.mutedForeground)
                            Text(item.date)
                                .cedTextStyle(.caption)
                                .foregroundStyle(CEDColor.mutedForeground)
                        }
                        .padding(.bottom, 12)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// One memory: a tinted photo placeholder with the title, quote and date below.
private struct MemoryCard: View {
    let memory: ScrapbookMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            memory.tint
                .frame(height: 96)
                .overlay {
                    if let imageURL = memory.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else if phase.error != nil {
                                CEDIconView(icon: .image, size: 32, color: CEDColor.mutedForeground)
                            } else {
                                ProgressView().tint(CEDColor.primary)
                            }
                        }
                    } else {
                        CEDIconView(icon: .image, size: 32, color: CEDColor.mutedForeground)
                    }
                }
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text(memory.title)
                    .cedTextStyle(.captionBold)
                    .foregroundStyle(CEDColor.foreground)
                if let reflection = memory.reflection {
                    Text("\"\(reflection)\"")
                        .cedTextStyle(.memoryQuote)
                        .foregroundStyle(CEDColor.mutedForeground)
                        .padding(.top, 2)
                }
                Text(memory.date)
                    .cedTextStyle(.small)
                    .foregroundStyle(CEDColor.hint)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(CEDColor.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: CEDRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: CEDRadius.xl).strokeBorder(CEDColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ScrapbookView()
        .environment(AppRouter(start: .scrapbook))
        .environment(JourneyStore())
}
