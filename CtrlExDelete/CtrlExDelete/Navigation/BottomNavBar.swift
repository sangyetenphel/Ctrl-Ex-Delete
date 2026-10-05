import SwiftUI

/// The five-tab bar shown under every screen after the check-in.
struct BottomNavBar: View {
    @Environment(AppRouter.self) private var router

    private struct Item {
        let label: String
        let screen: AppScreen
        let icon: CEDIcon
    }

    private let items = [
        Item(label: "Room", screen: .room, icon: .home),
        Item(label: "Activity", screen: .activities, icon: .clock),
        Item(label: "Support", screen: .talk, icon: .phone),
        Item(label: "Story", screen: .scrapbook, icon: .book),
        Item(label: "Progress", screen: .progress, icon: .chart),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.label) { item in
                let isActive = router.current == item.screen
                let color = isActive ? CEDColor.primary : CEDColor.mutedForeground

                Button {
                    router.go(to: item.screen)
                } label: {
                    VStack(spacing: 2) {
                        CEDIconView(icon: item.icon, size: 22, color: color)
                        Text(item.label)
                            .cedTextStyle(.navLabel)
                            .foregroundStyle(color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(CEDColor.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(CEDColor.border).frame(height: 1)
        }
    }
}
