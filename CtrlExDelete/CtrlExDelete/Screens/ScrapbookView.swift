import SwiftUI

/// "Your Journey": a celebration, recent memories (one row you swipe
/// through) and every memory, grouped by month like a photo journal.
struct ScrapbookView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey

    @State private var memoryToDelete: ScrapbookMemory?
    @State private var deleteError: String?

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
                    memoriesByMonth

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
        .confirmationDialog(
            "Delete this memory?",
            isPresented: Binding(get: { memoryToDelete != nil }, set: { if !$0 { memoryToDelete = nil } }),
            titleVisibility: .visible,
            presenting: memoryToDelete
        ) { memory in
            Button("Delete memory", role: .destructive) { delete(memory) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its photo and reflection will be removed. The activity still counts as completed.")
        }
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

            Text(StoryText.memoriesCollected(journey.memories.count))
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

            if let deleteError {
                Text(deleteError)
                    .cedTextStyle(.body)
                    .foregroundStyle(CEDColor.rose)
            }

            if journey.memories.isEmpty {
                Text(memoriesPlaceholder)
                    .cedTextStyle(.body)
                    .foregroundStyle(CEDColor.mutedForeground)
            }

            if !journey.memories.isEmpty {
                memoriesRow
            }
        }
    }

    /// Every memory in one row, newest first. About two cards fit on screen
    /// and the next one peeks in; swipe to see older ones. Cards share the
    /// height of the tallest one.
    private var memoriesRow: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(journey.memories) { memory in
                    memoryCard(memory)
                        .containerRelativeFrame(.horizontal) { width, _ in
                            (width - 12) / 2.15
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        // Run edge to edge, so cards scroll under the screen's side margins.
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .padding(.horizontal, -24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent memories, newest first")
    }

    /// Long-press a memory for "Delete memory".
    private func memoryCard(_ memory: ScrapbookMemory, compact: Bool = false) -> some View {
        MemoryCard(memory: memory, compact: compact)
            .contextMenu {
                Button("Delete memory", systemImage: "trash", role: .destructive) {
                    memoryToDelete = memory
                }
            }
            .accessibilityAction(named: "Delete memory") { memoryToDelete = memory }
    }

    private func delete(_ memory: ScrapbookMemory) {
        deleteError = nil
        Task {
            do {
                try await journey.deleteMemory(id: memory.id)
            } catch {
                deleteError = "That memory wasn\u{2019}t deleted. \(error.localizedDescription)"
            }
        }
    }

    private var memoriesPlaceholder: String {
        if !journey.hasLoaded { return "Loading your memories\u{2026}" }
        if let error = journey.loadError { return "Your memories couldn\u{2019}t be loaded. \(error)" }
        return "Your memories will show up here after your first reflection."
    }

    /// Every memory, newest month first ("November 2026", then "October
    /// 2026"), two per row, from the memories already loaded. Hidden until
    /// there's a memory (the row above explains why it's empty).
    @ViewBuilder
    private var memoriesByMonth: some View {
        let groups = StoryText.byMonth(journey.memories.map { ($0.id, $0.localDate) })
        if !groups.isEmpty {
            let byId = Dictionary(journey.memories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            VStack(alignment: .leading, spacing: 16) {
                Text("Your memories")
                    .cedTextStyle(.sectionTitle)
                    .foregroundStyle(CEDColor.foreground)
                    .accessibilityAddTraits(.isHeader)

                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .textCase(.uppercase)
                            .cedTextStyle(.captionBold.tracking(0.6))
                            .foregroundStyle(CEDColor.mutedForeground)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                                            GridItem(.flexible(), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(group.ids, id: \.self) { id in
                                if let memory = byId[id] {
                                    memoryCard(memory, compact: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}

/// One memory: a tinted photo placeholder with the title, quote and date below.
/// `compact` (the month grid) leaves out the quote and keeps titles to two lines.
private struct MemoryCard: View {
    let memory: ScrapbookMemory
    var compact = false

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
                Group {
                    if compact {
                        Text(memory.title).lineLimit(2, reservesSpace: true)
                    } else {
                        Text(memory.title)
                    }
                }
                .cedTextStyle(.captionBold)
                .foregroundStyle(CEDColor.foreground)
                if !compact, let reflection = memory.reflection {
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
