import SwiftUI

// TEMPORARY: simple stand-ins for the screens that have not been built yet.
// Each one is clearly labeled and links onward so the whole flow can be tapped through.
// Replace them one by one with the real screens from the Figma Make prototype.

struct PlaceholderScreen: View {
    struct Link {
        let title: String
        let destination: AppScreen
    }

    @Environment(AppRouter.self) private var router

    let title: String
    let summary: String
    var links: [Link] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Placeholder · coming next")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow)
                .foregroundStyle(CEDColor.rose)
                .padding(.bottom, 6)

            Text(title)
                .cedTextStyle(.screenTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text(summary)
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 6)

            VStack(spacing: 12) {
                ForEach(links, id: \.title) { link in
                    PrimaryButton(title: link.title) {
                        router.go(to: link.destination)
                    }
                }
            }
            .padding(.top, 28)

            Spacer()

            Button("Start over from the welcome screen") {
                router.go(to: .welcome)
            }
            .cedTextStyle(.bodySemibold)
            .foregroundStyle(CEDColor.mutedForeground)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CEDColor.background)
    }
}

/// Picks the placeholder for each screen that is still to be built.
struct UpcomingScreen: View {
    let screen: AppScreen

    var body: some View {
        switch screen {
        case .room:
            PlaceholderScreen(
                title: "Your Healing Room",
                summary: "Temporary destination. The pixel-art room with Ced, the scrapbook and the telephone goes here.",
                links: [
                    .init(title: "View today\u{2019}s activity", destination: .activities),
                    .init(title: "Open scrapbook", destination: .scrapbook),
                    .init(title: "Talk instead", destination: .talk),
                ]
            )
        case .reflection:
            PlaceholderScreen(
                title: "You showed up.",
                summary: "Photo placeholder, short note and how the activity felt.",
                links: [.init(title: "Add to my scrapbook", destination: .scrapbook)]
            )
        case .talk:
            PlaceholderScreen(
                title: "Say it here first.",
                summary: "Unsent message, sample chat with Ced and the human-support sheet.",
                links: [.init(title: "Return to my room", destination: .room)]
            )
        case .scrapbook:
            PlaceholderScreen(
                title: "Look how far you\u{2019}ve come.",
                summary: "Recent memories, the add-memory button and your story so far.",
                links: [.init(title: "View your insights \u{2192}", destination: .progress)]
            )
        case .progress:
            PlaceholderScreen(
                title: "Your patterns.",
                summary: "Week and month charts, activity breakdown and observations.",
                links: [.init(title: "Moving-forward check-in \u{2192}", destination: .movingForward)]
            )
        case .movingForward:
            PlaceholderScreen(
                title: "Do you feel ready to close this chapter?",
                summary: "Reflection questions and the ready / not-ready choice.",
                links: [
                    .init(title: "I\u{2019}m ready to move forward", destination: .finalGift),
                    .init(title: "I\u{2019}m not ready yet", destination: .room),
                ]
            )
        case .finalGift:
            PlaceholderScreen(
                title: "This chapter belongs to you.",
                summary: "Ced, the keepsake download and closing options."
            )
        case .welcome, .checkIn, .activities:
            EmptyView() // These are real screens, shown by ContentView.
        }
    }
}
