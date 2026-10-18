import SwiftUI

/// "Your patterns.": week / month charts of urges and moods, what the user
/// made time for, and gentle observations. Everything comes from
/// `GET /insights`, calculated from the user's own records.
struct ProgressInsightsView: View {
    @Environment(AppRouter.self) private var router
    @State private var period = InsightsPeriod.week
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

        // Both charts look and behave the same; only their data differs.
        BarChartCard(
            title: "Urge to reach out",
            subtitle: "Your daily urge to contact your ex. Lower bars mean a lower urge.",
            emptyNote: data.hasUrges ? nil : "Your check-ins will appear here.",
            points: data.urges,
            barColor: CEDColor.foreground
        )

        BarChartCard(
            title: "Mood after activities",
            subtitle: "How you felt compared with before. Higher bars mean you reported feeling better.",
            emptyNote: data.hasMoods ? nil : "Your answers will appear here after you finish an activity.",
            points: data.moods,
            barColor: Color(hex: 0x4A8A30)
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

/// A bar chart on a fixed 0–10 scale: bars start at zero and 10 fills the
/// full 100pt, so heights compare across weeks. Days without data are gaps
/// (a short grey stub), never zero. The chart doesn't react to touch: no
/// highlights or numbers. VoiceOver reads each bar's date and what was recorded.
private struct BarChartCard: View {
    let title: String
    let subtitle: String
    let emptyNote: String?
    let points: [ChartPoint]
    let barColor: Color

    private let chartHeight: CGFloat = 100
    private let scaleMaximum = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .padding(.bottom, 20) // 16 below the subtitle + the prototype's empty 4pt row

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points.indices, id: \.self) { index in
                    bar(at: index)
                }
            }
            .frame(height: chartHeight)

            HStack(spacing: 6) {
                ForEach(points) { point in
                    Text(point.label)
                        .cedTextStyle(.tiny)
                        .foregroundStyle(CEDColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .accessibilityHidden(true) // each bar already says its date

            if let emptyNote {
                Text(emptyNote)
                    .cedTextStyle(.small)
                    .foregroundStyle(CEDColor.hint)
                    .padding(.top, 14)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func bar(at index: Int) -> some View {
        let point = points[index]
        if let value = point.value {
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                .fill(barColor)
                .frame(height: CGFloat(min(max(value, 0), scaleMaximum) / scaleMaximum) * chartHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityElement()
                .accessibilityLabel(point.accessibilityText)
        } else {
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                .fill(CEDColor.border)
                .frame(height: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityElement()
                .accessibilityLabel(point.accessibilityText)
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
