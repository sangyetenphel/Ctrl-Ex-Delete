import SwiftUI

/// Daily check-in: four questions, a progress bar that fills as each one is
/// answered, and a button into the healing room once everything is answered.
/// The button saves the check-in to the backend and only moves on once the
/// server confirms it was saved.
struct CheckInView: View {
    @Environment(AppRouter.self) private var router
    @State private var answers = CheckInAnswers()
    @State private var submission = Submission.idle

    private enum Submission: Equatable {
        case idle
        case saving
        case failed(String)
        case saved
    }

    private var isBusy: Bool { submission == .saving || submission == .saved }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Group {
                        emotionSection
                        urgeSection
                        energySection
                        hardestSection
                    }
                    // Answers can't change while they're being saved.
                    .disabled(isBusy)

                    if case .failed(let message) = submission {
                        errorBanner(message)
                    }

                    PrimaryButton(title: buttonTitle, isEnabled: answers.isComplete && !isBusy) {
                        submit()
                    }
                    .padding(.bottom, 8)
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
        }
        .background(CEDColor.checkInBackground)
        .overlay(alignment: .bottom) {
            if submission == .saved {
                ToastView(message: "Check-in saved")
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Saving

    private var buttonTitle: String {
        switch submission {
        case .saving: "Saving your check-in\u{2026}"
        case .saved: "Saved"
        case .idle, .failed: "Enter my room \u{2192}"
        }
    }

    private func submit() {
        // isBusy also blocks a second tap while the first save is in flight.
        guard !isBusy, let request = answers.makeRequest() else { return }
        withAnimation(.easeOut(duration: 0.2)) { submission = .saving }

        Task {
            do {
                _ = try await APIClient.shared.submitCheckIn(request)
                withAnimation(.easeOut(duration: 0.2)) { submission = .saved }
                AccessibilityNotification.Announcement("Check-in saved").post()
                // Let the confirmation show briefly before moving on.
                try? await Task.sleep(for: .seconds(1))
                router.go(to: .room)
            } catch {
                withAnimation(.easeOut(duration: 0.2)) {
                    submission = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your check-in wasn\u{2019}t saved")
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.foreground)
            Text(message)
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
            Button("Try again", action: submit)
                .cedTextStyle(.bodyBold)
                .foregroundStyle(CEDColor.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CEDRadius.lg)
                .strokeBorder(CEDColor.rose, lineWidth: 2)
        )
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Day 1")
                .textCase(.uppercase)
                .cedTextStyle(.eyebrow)
                .foregroundStyle(CEDColor.primary)
                .padding(.bottom, 6)

            Text("Where are you\nright now?")
                .cedTextStyle(.screenTitle)
                .foregroundStyle(CEDColor.foreground)
                .accessibilityAddTraits(.isHeader)

            Text("No judgment. This helps us meet you where you are today.")
                .cedTextStyle(.body)
                .foregroundStyle(CEDColor.mutedForeground)
                .padding(.top, 6)

            CheckInProgressBar(steps: answers.answeredSteps)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(CEDColor.card.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CEDColor.border).frame(height: 1)
        }
    }

    // MARK: Questions

    private var emotionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("How are you feeling?")

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    emotionCard(.heavy)
                    emotionCard(.gettingThrough)
                }
                GridRow {
                    emotionCard(.missingThem)
                    emotionCard(.hopeful)
                }
            }
        }
    }

    private func emotionCard(_ emotion: Emotion) -> some View {
        Button {
            answers.emotion = emotion
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                CEDIconView(icon: emotion.icon, size: 28, color: emotion.iconColor)
                    .padding(.bottom, 8)
                Text(emotion.label)
                    .cedTextStyle(.bodyBold)
                    .foregroundStyle(CEDColor.foreground)
                Text(emotion.subtitle)
                    .cedTextStyle(.caption)
                    .foregroundStyle(CEDColor.mutedForeground)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            // Both cards in a row stretch to the same height, like the CSS grid.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .selectableBackground(isSelected: answers.emotion == emotion, cornerRadius: CEDRadius.xl)
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private var urgeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("How strong is the urge to contact them?")
                Spacer(minLength: 8)
                Text("\(answers.urge)")
                    .cedTextStyle(.bigNumber)
                    .foregroundStyle(CEDColor.primary)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 4)

            HStack {
                Text("Not at all")
                Spacer()
                Text("Very strong")
            }
            .cedTextStyle(.small)
            .foregroundStyle(CEDColor.mutedForeground)
            .padding(.bottom, 4)

            UrgeSlider(value: $answers.urge, range: SampleData.urgeRange) {
                answers.hasAnsweredUrge = true
            }

            HStack(spacing: 0) {
                ForEach(Array(SampleData.urgeRange), id: \.self) { number in
                    Text("\(number)")
                    if number != SampleData.urgeRange.upperBound { Spacer(minLength: 0) }
                }
            }
            .cedTextStyle(.tiny)
            .foregroundStyle(CEDColor.hint)
            .padding(.top, 4)
            .accessibilityHidden(true)
        }
    }

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("How is your energy today?")

            HStack(spacing: 8) {
                ForEach(EnergyLevel.allCases) { level in
                    let isSelected = answers.energy == level
                    Button {
                        answers.energy = level
                    } label: {
                        Text(level.label)
                            .cedTextStyle(.bodyBold)
                            .foregroundStyle(isSelected ? CEDColor.primary : CEDColor.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .selectableBackground(isSelected: isSelected, cornerRadius: CEDRadius.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hardestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What feels hardest right now?")

            FlowLayout(spacing: 8) {
                ForEach(HardestArea.allCases) { item in
                    let isSelected = answers.hardestThings.contains(item)
                    Button {
                        answers.toggleHardestThing(item)
                    } label: {
                        Text(item.label)
                            .cedTextStyle(.bodySemibold)
                            .foregroundStyle(isSelected ? CEDColor.primary : CEDColor.mutedForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .selectableBackground(isSelected: isSelected, cornerRadius: 100)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .cedTextStyle(.bodyBold)
            .foregroundStyle(CEDColor.foreground)
    }
}

/// Four thin bars, one per question, that fill in as answers are given.
private struct CheckInProgressBar: View {
    let steps: [Bool]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(CEDColor.border)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(CEDColor.primary)
                                .frame(width: steps[index] ? geometry.size.width : 0)
                        }
                    }
                    .clipShape(Capsule())
                    .frame(height: 6)
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: steps)
        .accessibilityElement()
        .accessibilityLabel("Check-in progress")
        .accessibilityValue("\(steps.filter { $0 }.count) of \(steps.count) answered")
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    CheckInView()
        .environment(AppRouter())
}
