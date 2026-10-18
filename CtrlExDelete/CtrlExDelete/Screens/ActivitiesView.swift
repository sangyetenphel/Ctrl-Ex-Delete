import SwiftUI

/// The Activity tab.
/// - With an activity in progress: that activity, "Continue my reflection"
///   and "Change activity". Only one activity can be in progress at a time.
/// - Otherwise: the recommendations for the latest check-in, one card at a
///   time: swipe left for the next one, right for the previous one. "I'll
///   try this" and "Save for later" stay below and act on the visible card.
struct ActivitiesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(JourneyStore.self) private var journey
    @State private var loadState = LoadState.loading
    @State private var deck = ActivityDeck(activities: [])
    /// The card the horizontal pager is showing (its index). Kept in step
    /// with `deck.index`, which the buttons act on.
    @State private var visibleCard: Int?
    /// How the user said they feel in the check-in these cards came from.
    @State private var checkInFeeling: Emotion?
    @State private var isWorking = false
    /// True from tapping "I'll try this" until the reflection opens. The deck
    /// stays on screen meanwhile, so the in-progress page doesn't flash by.
    @State private var isStartingActivity = false
    @State private var actionError: String?
    @State private var isConfirmingChange = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    private enum LoadState: Equatable {
        case loading
        case loaded
        case noCheckIn          // nothing to base recommendations on yet
        case noRecommendations  // checked in, but the server returned no cards
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let current = journey.selectedActivity, !isStartingActivity {
                inProgressView(current)   // returning later to an unfinished activity
            } else {
                switch loadState {
                case .loading:
                    messageView(title: nil, message: "Finding activities for today\u{2026}", showsSpinner: true)
                case .loaded:
                    deckView
                case .noCheckIn:
                    messageView(
                        title: "Check in first",
                        message: "Your activities are picked from today\u{2019}s check-in.",
                        buttonTitle: "Begin today\u{2019}s check-in"
                    ) { router.go(to: .checkIn) }
                case .noRecommendations:
                    // E.g. the latest check-in's activities were retired from
                    // the catalog: a new check-in brings fresh ones.
                    messageView(
                        title: "No activities yet",
                        message: "There aren\u{2019}t any activities for your latest check-in right now. A new check-in will bring fresh ideas.",
                        buttonTitle: "Begin today\u{2019}s check-in"
                    ) { router.go(to: .checkIn) }
                case .failed(let message):
                    messageView(
                        title: "Couldn\u{2019}t load activities",
                        message: message,
                        buttonTitle: "Try again"
                    ) { Task { await loadRecommendations() } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CEDColor.background)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .alert("Change activity?", isPresented: $isConfirmingChange) {
            Button("Keep going", role: .cancel) {}
            Button("Change activity", role: .destructive, action: changeActivity)
        } message: {
            Text("Your current activity will be set aside. It won\u{2019}t count as completed, and the memories you\u{2019}ve saved stay as they are.")
        }
        .task { await loadRecommendations() }
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: Activity in progress

    private func inProgressView(_ current: SelectedActivity) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ActivityCard(activity: current.activity)
                    .padding(.bottom, 16)

                HStack(spacing: 8) {
                    Circle()
                        .fill(CEDColor.sproutGreen)
                        .frame(width: 8, height: 8)
                    Text(current.startedOn.isEmpty ? "In progress" : "In progress \u{B7} chosen \(current.startedOn)")
                        .cedTextStyle(.captionBold)
                        .foregroundStyle(CEDColor.mutedForeground)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .accessibilityElement(children: .combine)

                PrimaryButton(title: "Continue my reflection") {
                    router.go(to: .reflection)
                }

                Text("Finish this one with a short reflection before choosing another.")
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button(isWorking ? "Changing\u{2026}" : "Change activity") {
                    isConfirmingChange = true
                }
                .cedTextStyle(.bodySemibold)
                .foregroundStyle(CEDColor.mutedForeground)
                .disabled(isWorking)
                .padding(.top, 16)

                errorText
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// "Change activity", after the confirmation.
    private func changeActivity() {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        Task {
            defer { isWorking = false }
            do {
                try await journey.abandonCurrentActivity()
                await loadRecommendations()
            } catch {
                actionError = "Your activity wasn\u{2019}t changed. \(error.localizedDescription)"
            }
        }
    }

    // MARK: Recommendations

    private var deckView: some View {
        ScrollView {
            VStack(spacing: 0) {
                cardPager
                    .padding(.bottom, 20)

                VStack(spacing: 0) {
                    pageDots
                        .padding(.bottom, 20)

                    actionButtons

                    errorText
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// The cards side by side in a native paging scroll view. Only browsing:
    /// swiping never starts, saves or completes anything. Each card keeps its
    /// full height (no text is cut off); the pager is as tall as the longest,
    /// so the dots and buttons below don't jump, and the page itself scrolls
    /// vertically as before.
    private var cardPager: some View {
        ScrollView(.horizontal) {
            // Spacing = the side margins, so the next card waits just off screen.
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(deck.activities.enumerated()), id: \.offset) { index, activity in
                    ActivityCard(activity: activity)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                        // VoiceOver: one card at a time; swipe up or down on it
                        // to move between recommendations.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Activity \(index + 1) of \(deck.activities.count). \(activity.category). \(activity.title). \(activity.instructions) Why this fits today: \(activity.whyItFits)")
                        .accessibilityValue(activity.isCompleted ? "Completed" : activity.isSaved ? "Saved for later" : "")
                        .accessibilityHint(deck.activities.count > 1 ? "Swipe up or down to hear other activities." : "")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: showCard(deck.index + 1)
                            case .decrement: showCard(deck.index - 1)
                            @unknown default: break
                            }
                        }
                        .accessibilityHidden(index != deck.index)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleCard)
        .scrollIndicators(.hidden)
        // The card being started or saved stays on screen until that's done.
        .scrollDisabled(isWorking)
        .onChange(of: visibleCard) { _, index in
            if let index { deck.go(to: index) }
        }
    }

    /// Moves the pager (dots, VoiceOver) to `index`, with the paging animation.
    private func showCard(_ index: Int) {
        guard deck.activities.indices.contains(index), !isWorking else { return }
        withAnimation(.easeInOut(duration: 0.3)) { visibleCard = index }
        deck.go(to: index)
        AccessibilityNotification.Announcement(deck.current.title).post()
    }

    @ViewBuilder private var errorText: some View {
        if let actionError {
            Text(actionError)
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.rose)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
    }

    private func loadRecommendations() async {
        if loadState != .loaded { loadState = .loading }
        do {
            let response = try await APIClient.shared.latestRecommendations()
            checkInFeeling = response.checkIn?.feeling
            if response.checkInId == nil {
                loadState = .noCheckIn
            } else if response.recommendations.isEmpty {
                loadState = .noRecommendations
            } else {
                var newDeck = ActivityDeck(activities: response.recommendations.map(Activity.init))
                // Reloading the same cards keeps the one the user was looking at.
                if newDeck.activities.map(\.recommendationId) == deck.activities.map(\.recommendationId) {
                    newDeck.go(to: deck.index)
                }
                deck = newDeck
                visibleCard = deck.index
                loadState = .loaded
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// "I'll try this": starts the activity (in progress, not completed) and
    /// opens its reflection. Completion happens when the reflection is saved.
    private func selectCurrentActivity() {
        // isWorking also blocks repeated taps while the first request is out.
        guard !isWorking, !deck.current.isCompleted else { return }
        isWorking = true
        isStartingActivity = true
        actionError = nil
        let activity = deck.current

        Task {
            defer { isWorking = false }
            do {
                try await journey.select(activity)
                // Straight to its reflection; isStartingActivity stays true so
                // this screen keeps showing the deck while it fades out.
                router.go(to: .reflection)
            } catch APIError.server(status: 404, _) {
                // This card no longer exists (e.g. the test data was reset):
                // show what the server has now, usually "check in first".
                isStartingActivity = false
                await loadRecommendations()
            } catch {
                isStartingActivity = false
                actionError = "Your choice wasn\u{2019}t saved. \(error.localizedDescription)"
            }
        }
    }

    /// "Save for later" on or off. Saved activities come first next time.
    private func toggleSaved() {
        guard !isWorking else { return }
        let activity = deck.current
        let isSaved = !activity.isSaved
        isWorking = true
        actionError = nil
        deck.setSaved(isSaved, activityId: activity.activityId)   // show it right away

        Task {
            defer { isWorking = false }
            do {
                try await journey.setSaved(isSaved, activityId: activity.activityId)
                showToast(isSaved ? "Saved for later" : "Removed from saved")
            } catch {
                deck.setSaved(!isSaved, activityId: activity.activityId)
                actionError = "That change wasn\u{2019}t saved. \(error.localizedDescription)"
            }
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
        AccessibilityNotification.Announcement(message).post()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { toastMessage = nil }
        }
    }

    // MARK: Loading, empty and error messages

    private func messageView(
        title: String?,
        message: String,
        showsSpinner: Bool = false,
        buttonTitle: String? = nil,
        action: @escaping () -> Void = {}
    ) -> some View {
        VStack(spacing: 12) {
            if showsSpinner {
                ProgressView()
                    .tint(CEDColor.primary)
            }
            if let title {
                Text(title)
                    .cedTextStyle(.cardTitle)
                    .foregroundStyle(CEDColor.foreground)
            }
            Text(message)
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .multilineTextAlignment(.center)
            if let buttonTitle {
                PrimaryButton(title: buttonTitle, action: action)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .padding(.top, 40)
    }

    // MARK: Header

    private var header: some View {
        let isInProgress = journey.selectedActivity != nil && !isStartingActivity
        return VStack(alignment: .leading, spacing: 0) {
            Text("Day \(journey.dayNumber)")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow)
                .foregroundStyle(CEDColor.primary)
                .padding(.bottom, 4)

            Text(isInProgress ? "One small step at a time." : Self.heading(for: checkInFeeling))
                .cedTextStyle(.pageTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text(isInProgress ? "Here\u{2019}s the activity you chose." : "Pick something that feels doable.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// The page heading follows how the user said they feel today.
    /// "Heavy" keeps the prototype's wording.
    private static func heading(for feeling: Emotion?) -> String {
        switch feeling {
        case .heavy: "Today seems a little heavy."
        case .gettingThrough: "You\u{2019}re getting through it."
        case .missingThem: "Missing them is hard today."
        case .hopeful: "Today feels a little lighter."
        case nil: "Activities for today."
        }
    }

    // MARK: Dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(deck.activities.indices, id: \.self) { index in
                Button {
                    showCard(index)
                } label: {
                    Circle()
                        .fill(index == deck.index ? CEDColor.primary : CEDColor.border)
                        .frame(width: 8, height: 8)
                        // Bigger invisible tap area without changing the spacing.
                        .padding(8)
                        .contentShape(Rectangle())
                        .padding(-8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Activity \(index + 1) of \(deck.activities.count)")
                .accessibilityAddTraits(index == deck.index ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: I'll try this / Save for later

    private var actionButtons: some View {
        let activity = deck.current
        return HStack(spacing: 12) {
            Button(action: selectCurrentActivity) {
                Text(activity.isCompleted ? "Completed \u{2713}"
                     : isStartingActivity ? "Starting\u{2026}" : "I\u{2019}ll try this")
                    .cedTextStyle(.bodyBold)
                    .foregroundStyle(CEDColor.cream)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 14)
                    .background(CEDColor.primary, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
                    .opacity(activity.isCompleted ? 0.6 : 1)
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(isWorking || activity.isCompleted)
            .accessibilityHint(activity.isCompleted ? "You already completed this activity." : "Starts this activity and opens its reflection.")

            Button(action: toggleSaved) {
                HStack(spacing: 6) {
                    CEDIconView(
                        icon: activity.isSaved ? .bookmarkFilled : .bookmark,
                        size: 22,
                        color: CEDColor.accent
                    )
                    Text(activity.isSaved ? "Saved" : "Save for later")
                }
                .actionButtonLabel(
                    textColor: activity.isSaved ? CEDColor.accent : CEDColor.mutedForeground,
                    borderColor: activity.isSaved ? CEDColor.accent : CEDColor.border
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityHint(activity.isSaved ? "Removes it from your saved activities." : "Saved activities come first in your next recommendations.")
        }
        // Both buttons share the height of the taller one.
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Activity card

/// The rounded card: tinted art area with the icon and category pill, then
/// a white section with the title, instructions and "Why this fits today".
private struct ActivityCard: View {
    let activity: Activity

    var body: some View {
        VStack(spacing: 0) {
            artArea
            details
        }
        .background(activity.background)
        .clipShape(RoundedRectangle(cornerRadius: CEDRadius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: CEDRadius.xxl)
                .strokeBorder(CEDColor.border, lineWidth: 1)
        )
    }

    private var artArea: some View {
        VStack(spacing: 8) {
            CEDIconView(icon: activity.icon, size: 32, color: activity.accent)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: CEDRadius.xl))

            Text(activity.category)
                .cedTextStyle(.captionBold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(activity.accent, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .background(activity.background)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            // fixedSize(vertical): in the horizontal pager, text must still
            // wrap to its full height instead of being cut off with "…".
            Text(activity.title)
                .cedTextStyle(.cardTitle)
                .foregroundStyle(CEDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(activity.instructions)
                .cedTextStyle(.bodyRelaxed)
                .foregroundStyle(CEDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text("Why this fits today")
                    .textCase(.uppercase)
                    .cedTextStyle(.captionBold.tracking(0.6))
                    .foregroundStyle(CEDColor.primary)
                Text(activity.whyItFits)
                    .cedTextStyle(.bodyRelaxed)
                    .foregroundStyle(CEDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(CEDColor.secondary, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(CEDColor.card)
    }
}

// MARK: - Shared look for the Save for later button

private extension View {
    func actionButtonLabel(textColor: Color, borderColor: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: CEDRadius.xl)
        return self
            .cedTextStyle(.bodyBold)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 14)
            .background(CEDColor.card, in: shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: 2))
            .contentShape(shape)
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    ActivitiesView()
        .environment(AppRouter())
        .environment(JourneyStore())
}
