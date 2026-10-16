import SwiftUI

/// "Your patterns.": week / month charts of urges and moods, what the user
/// made time for, and gentle observations. Everything comes from
/// `GET /insights`, calculated from the user's own records.
struct ProgressInsightsView: View {
    @Environment(AppRouter.self) private var router
    @State private var period = InsightsPeriod.week
    @State private var tappedUrge: Int?
    @State private var tappedMood: Int?
    @State private var loadState = LoadState.loading

    private enum LoadState {
        case loading
        case loaded(InsightsData)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                VStack(spacing: 20) {
                    switch loadState {
                    case .loading:
                        ProgressView()
                            .tint(CEDColor.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    case .failed(let message):
                        VStack(spacing: 12) {
                            Text("Your insights couldn\u{2019}t be loaded")
                                .cedTextStyle(.bodyBold)
                                .foregroundStyle(CEDColor.foreground)
                            Text(message)
                                .cedTextStyle(.body)
                                .foregroundStyle(CEDColor.mutedForeground)
                                .multilineTextAlignment(.center)
                            PrimaryButton(title: "Try again", isCompact: true) {
                                Task { await load() }
                            }
                        }
                        .cardStyle()
                    case .loaded(let data):
                        cards(for: data)
                    }

                    OutlineButton(title: "Moving-forward check-in \u{2192}") {
                        router.go(to: .movingForward)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.hidden)
        .statusBarBackground(CEDColor.card)
        .background(CEDColor.background)
        // Runs when the screen opens (so new check-ins and reflections show
        // up) and again whenever the period changes.
        .task(id: period) { await load() }
    }

    private func load() async {
        if case .loaded = loadState {} else { loadState = .loading }
        do {
            let dto = try await APIClient.shared.insights(
                period: period,
                today: CheckInAnswers.localDateText(for: .now)
            )
            loadState = .loaded(InsightsData(dto))
        } catch is CancellationError {
            // The period changed again; the newer request takes over.
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func cards(for data: InsightsData) -> some View {
        takeawayCard(data)

        BarChartCard(
            title: "Urges to reach out",
            subtitle: "Rated 1\u{2013}10 at each check-in",
            footnote: data.period == .week
                ? "Tap a bar to see the rating. Gaps are days without a check-in."
                : "Each bar is a week\u{2019}s average. Tap a bar to see it. Gaps are weeks without a check-in.",
            points: data.urges,
            maxValue: 10,
            valueText: { "\($0)" },
            accessibilityValue: { "\($0) out of 10" },
            barColor: CEDColor.hint,
            tappedBarColor: CEDColor.foreground,
            valueColor: CEDColor.primary,
            tappedIndex: $tappedUrge
        )

        BarChartCard(
            title: "Mood after activities",
            subtitle: "How you felt compared to before, after each activity",
            footnote: data.moodTotal == 0
                ? "Your answers will appear here after you finish an activity."
                : "Each bar counts how often you chose that answer. Tap a bar to see the number.",
            points: data.moods,
            maxValue: max(1, data.moods.compactMap(\.value).max() ?? 1),
            valueText: { "\($0)" },
            accessibilityValue: { $0 == 1 ? "once" : "\($0) times" },
            barColor: Color(hex: 0x6BA84A),
            tappedBarColor: Color(hex: 0x4A8A30),
            valueColor: Color(hex: 0x4A8A30),
            tappedIndex: $tappedMood
        )

        breakdownCard(data)
        observationsCard(data)
    }

    // MARK: Header with the week / month switch

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Insights")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow)
                .foregroundStyle(CEDColor.primary)
                .padding(.bottom, 4)

            Text("Your patterns.")
                .cedTextStyle(.screenTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("Small moments, over time.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 4)

            HStack(spacing: 0) {
                ForEach(InsightsPeriod.allCases) { option in
                    let isSelected = period == option
                    Button {
                        period = option
                        tappedUrge = nil
                        tappedMood = nil
                    } label: {
                        Text(option.label)
                            .cedTextStyle(.bodyBold)
                            .foregroundStyle(isSelected ? CEDColor.foreground : CEDColor.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(CEDColor.card)
                                        .shadow(color: CEDColor.foreground.opacity(0.1), radius: 1.5, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(CEDColor.secondary, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
            .padding(.top, 16)
        }
        .cardHeaderStyle()
    }

    // MARK: Cards

    private func takeawayCard(_ data: InsightsData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Main takeaway")
                .textCase(.uppercase)
                .cedTextStyle(.captionBold.tracking(0.6))
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.bottom, 4)
            Text(data.takeawayHeadline)
                .cedTextStyle(CEDTextStyle(font: .loraBold, size: 16, lineHeight: 22, relativeTo: .headline))
                .foregroundStyle(CEDColor.foreground)
                .padding(.bottom, 4)
            Text(data.takeawayBody)
                .cedTextStyle(.bodyRelaxed)
                .foregroundStyle(CEDColor.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(hex: 0xFFF3CC), in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .accessibilityElement(children: .combine)
    }

    private func breakdownCard(_ data: InsightsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you made time for")
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.foreground)
                .padding(.bottom, 4)

            ForEach(data.activities) { share in
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(share.label)
                            .cedTextStyle(.captionSemibold)
                            .foregroundStyle(CEDColor.foreground)
                        Spacer()
                        Text(share.count > 0 ? "\(share.count) \u{B7} \(share.percent)%" : "\u{2014}")
                            .cedTextStyle(.caption)
                            .foregroundStyle(CEDColor.mutedForeground)
                    }
                    Capsule()
                        .fill(CEDColor.border)
                        .frame(height: 8)
                        .overlay(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(share.color)
                                    .frame(width: geometry.size.width * CGFloat(share.percent) / 100)
                            }
                        }
                        .clipShape(Capsule())
                        .animation(.easeInOut(duration: 0.4), value: share.percent)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }

    private func observationsCard(_ data: InsightsData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Patterns you might recognize")
                .cedTextStyle(.serifBodyBold)
                .foregroundStyle(CEDColor.foreground)
                .padding(.bottom, 12)

            if data.observations.isEmpty {
                Text("As you check in and finish activities, patterns from your own days will show up here. There\u{2019}s no rush.")
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.mutedForeground)
            }

            ForEach(data.observations.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(CEDColor.border).frame(height: 1).padding(.vertical, 12)
                }
                Text(data.observations[index])
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.foreground)
            }

            // The prototype ends this card with a divider and an empty space
            // where "Is this accurate?" buttons used to be.
            Rectangle().fill(CEDColor.border).frame(height: 1).padding(.top, 16)
            Spacer().frame(height: 16)
        }
        .cardStyle()
    }
}

// MARK: - Bar chart

/// A simple bar chart where `maxValue` fills the full 100pt height. Tapping a
/// bar shows its value above the label; nil values show a short grey stub.
private struct BarChartCard: View {
    let title: String
    let subtitle: String
    let footnote: String
    let points: [ChartPoint]
    let maxValue: Int
    let valueText: (Int) -> String
    let accessibilityValue: (Int) -> String
    let barColor: Color
    let tappedBarColor: Color
    let valueColor: Color
    @Binding var tappedIndex: Int?

    private let chartHeight: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.foreground)
            Text(subtitle)
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 2)
                .padding(.bottom, 20) // 16 below the subtitle + the prototype's empty 4pt row

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points.indices, id: \.self) { index in
                    bar(at: index)
                }
            }
            .frame(height: chartHeight)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points.indices, id: \.self) { index in
                    VStack(spacing: 2) {
                        if tappedIndex == index, let value = points[index].value {
                            Text(valueText(value))
                                .cedTextStyle(.tinyBold)
                                .foregroundStyle(valueColor)
                        }
                        Text(points[index].label)
                            .cedTextStyle(.tiny)
                            .foregroundStyle(CEDColor.mutedForeground)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .accessibilityHidden(true)

            Text(footnote)
                .cedTextStyle(.small)
                .foregroundStyle(CEDColor.hint)
                .padding(.top, 14)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func bar(at index: Int) -> some View {
        let point = points[index]
        if let value = point.value {
            Button {
                tappedIndex = tappedIndex == index ? nil : index
            } label: {
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                    .fill(tappedIndex == index ? tappedBarColor : barColor)
                    .frame(height: CGFloat(value) / CGFloat(max(maxValue, 1)) * chartHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.15), value: tappedIndex)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(point.label): \(accessibilityValue(value))")
        } else {
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                .fill(CEDColor.border)
                .frame(height: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityLabel("\(point.label): nothing recorded")
        }
    }
}

private extension View {
    /// White rounded card with 16pt padding.
    func cardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ProgressInsightsView()
        .environment(AppRouter(start: .progress))
}
