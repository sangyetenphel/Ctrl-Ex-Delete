import SwiftUI

/// "Call Ced": a voice call, FaceTime-style but in the app's own colors,
/// with pixel Ced from the healing room in the middle.
///
/// Connecting: small Ced with soft ripples and "Calling Ced…".
/// Active: bigger Ced who breathes while listening and bobs with the voice
/// while speaking, the call time and status, and mute / speaker / end.
/// Crisis resources appear on this screen when needed, but nothing is ever
/// dialled or opened unless the user taps it.
struct CallCedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var call = CallSession()

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                avatar
                Text("Ced")
                    .cedTextStyle(CEDTextStyle(font: .loraBold, size: 30, lineHeight: 36, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .padding(.top, 28)
                status
                    .padding(.top, 6)
                Text("Ced is an AI companion, not a therapist or an emergency service.")
                    .cedTextStyle(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                Spacer(minLength: 12)

                // During the call and after it ends (resources flagged on the
                // call stay here), never while still connecting.
                if let support = call.support, call.phase != .connecting {
                    CallSupportPanel(support: support, showsDVHotline: call.showsDVHotline,
                                     open: { url in hangUp(thenOpen: url) },
                                     close: { withAnimation { call.hideSupport() } })
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                controls
                    .padding(.bottom, 28)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: call.phase)
        .animation(.easeInOut(duration: 0.3), value: call.support)
        .task { await call.start() }
        .onDisappear { call.end() }
    }

    // MARK: Background

    /// The app's blues, deepening toward the bottom like a night sky.
    private var background: some View {
        LinearGradient(colors: [CEDColor.accent, CEDColor.primary, Color(hex: 0x23394B)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) {
                // A soft glow behind Ced.
                RadialGradient(colors: [CEDColor.secondary.opacity(0.35), .clear],
                               center: .center, startRadius: 10, endRadius: 260)
                    .frame(height: 520)
                    .offset(y: 80)
            }
            .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            if call.isMock {
                Text("Practice mode \u{B7} mock voice")
                    .cedTextStyle(.captionBold)
                    .foregroundStyle(CEDColor.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CEDColor.peach, in: Capsule())
                    .accessibilityLabel("Practice mode. This is a mock voice, not the real Ced.")
            }
            Spacer()
            if call.phase != .connecting, call.support == nil {
                Button {
                    withAnimation { call.showSupport() }
                } label: {
                    Label("Support", systemImage: "heart.circle.fill")
                        .cedTextStyle(.captionBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .accessibilityHint("Shows 988 and emergency options")
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Ced

    private var avatar: some View {
        let isActive = call.phase == .active
        let size: CGFloat = isActive ? 190 : 130
        return ZStack {
            if call.phase == .connecting {
                ConnectingRipples(reduceMotion: reduceMotion)
                    .frame(width: 280, height: 280)
            }
            Circle()
                .fill(CEDColor.secondary.opacity(isActive ? 0.22 : 0.15))
                .frame(width: size * 1.35, height: size * 1.35)
                .scaleEffect(isActive && call.activity == .speaking ? 1 + CGFloat(call.level) * 0.12 : 1)
                .animation(.easeOut(duration: 0.15), value: call.level)

            CedFigure(activity: isActive ? call.activity : nil, level: call.level, reduceMotion: reduceMotion)
                .frame(width: size, height: size * 82 / 70)
        }
        .frame(height: 300)
        .accessibilityElement()
        .accessibilityLabel(isActive ? "Ced. \(call.activity.label)" : "Calling Ced")
    }

    @ViewBuilder
    private var status: some View {
        switch call.phase {
        case .connecting:
            Text("Calling Ced\u{2026}")
                .cedTextStyle(.bodyLarge)
                .foregroundStyle(.white.opacity(0.85))
        case .active:
            HStack(spacing: 6) {
                if let connectedAt = call.connectedAt {
                    TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                        Text(Self.duration(since: connectedAt, now: context.date))
                            .monospacedDigit()
                    }
                }
                Text("\u{B7}")
                Text(call.isMuted ? "Muted" : call.activity.label)
            }
            .cedTextStyle(.bodyLarge)
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityElement(children: .combine)
        case .ended(let reason):
            Text(reason)
                .cedTextStyle(.bodyLarge)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private static func duration(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch call.phase {
        case .connecting:
            CallControl(systemImage: "phone.down.fill", label: "End", style: .end) { hangUp() }
        case .active:
            HStack(spacing: 36) {
                CallControl(systemImage: call.isMuted ? "mic.slash.fill" : "mic.fill",
                            label: call.isMuted ? "Unmute" : "Mute",
                            style: call.isMuted ? .on : .off) { call.toggleMute() }
                CallControl(systemImage: call.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                            label: "Speaker",
                            style: call.isSpeakerOn ? .on : .off) { call.toggleSpeaker() }
                CallControl(systemImage: "phone.down.fill", label: "End", style: .end) { hangUp() }
            }
        case .ended:
            HStack(spacing: 12) {
                Button("Close") { dismiss() }
                    .cedTextStyle(.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.18), in: Capsule())
                Button("Call again") { callAgain() }
                    .cedTextStyle(.button)
                    .foregroundStyle(CEDColor.primary)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                    .accessibilityHint("Starts a new call with Ced")
            }
        }
    }

    /// A fresh call after one ended (dropped, timed out, or hung up).
    private func callAgain() {
        let next = CallSession()
        call = next
        Task { await next.start() }
    }

    /// Ends the call, then (only because the user tapped it) opens 988 or 911.
    /// If support came up during this call, hanging up stays on the ended
    /// screen with those resources ("Close" leaves); otherwise it closes as before.
    private func hangUp(thenOpen url: URL? = nil) {
        call.end()
        if url == nil, call.flaggedSupport != nil { return }
        dismiss()
        if let url { openURL(url) }
    }
}

// MARK: - Pixel Ced

/// The room's pixel Ced. Breathes while listening, floats gently while
/// thinking, and bobs with the voice while speaking.
private struct CedFigure: View {
    let activity: CallSession.Activity?
    let level: Float
    let reduceMotion: Bool
    @State private var breathe = false

    var body: some View {
        PixelCedArt()
            .scaleEffect(scale)
            .offset(y: offset)
            .animation(.easeOut(duration: 0.12), value: level)
            .animation(.easeInOut(duration: activity == .thinking ? 1.6 : 2.8).repeatForever(autoreverses: true),
                       value: breathe)
            .onAppear { if !reduceMotion { breathe = true } }
    }

    private var scale: CGFloat {
        switch activity {
        case .listening: breathe ? 1.035 : 1
        case .speaking: 1 + CGFloat(level) * 0.05
        default: 1
        }
    }

    private var offset: CGFloat {
        switch activity {
        case .speaking: -CGFloat(level) * 8
        case .thinking: breathe ? -6 : 0
        default: 0
        }
    }
}

/// Soft rings drifting outward while the call connects.
private struct ConnectingRipples: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let progress = (t / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(.white.opacity(0.35 * (1 - progress)), lineWidth: 2)
                        .scaleEffect(0.45 + progress * 0.55)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

private struct CallControl: View {
    enum Style { case off, on, end }

    let systemImage: String
    let label: String
    let style: Style
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(style == .on ? CEDColor.primary : .white)
                    .frame(width: 72, height: 72)
                    .background(background, in: Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(label)
            .accessibilityAddTraits(style == .on ? .isSelected : [])

            Text(label)
                .cedTextStyle(.captionSemibold)
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)
        }
    }

    private var background: Color {
        switch style {
        case .off: .white.opacity(0.18)
        case .on: .white
        case .end: Color(hex: 0xE5484D)
        }
    }
}

// MARK: - Crisis support during a call

/// 988 / 911 (and, for abuse or stalking, the National Domestic Violence
/// Hotline) on the call screen. Tapping one ends the call first (so the
/// phone's audio is free) and then opens the Phone or Messages app. Nothing
/// is ever dialled or opened without a tap.
private struct CallSupportPanel: View {
    let support: CrisisSupport
    var showsDVHotline = false
    let open: (URL) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(support == .danger ? "Your safety comes first" : "You don\u{2019}t have to carry this alone")
                    .cedTextStyle(.bodyBold)
                    .foregroundStyle(CEDColor.foreground)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CEDColor.mutedForeground)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Hide support options")
            }
            if support == .danger {
                button("Call 911", url: "tel:911", filled: true, hint: "Ends this call and calls emergency services")
            }
            if showsDVHotline {
                Text("National Domestic Violence Hotline")
                    .cedTextStyle(.captionBold)
                    .foregroundStyle(CEDColor.foreground)
                HStack(spacing: 8) {
                    button("Call hotline", url: "tel:18007997233", filled: false,
                           hint: "Ends this call and calls the National Domestic Violence Hotline, 1-800-799-7233")
                    button("Text START", url: "sms:88788&body=START", filled: false,
                           hint: "Ends this call and opens Messages to text START to 88788")
                }
            }
            HStack(spacing: 8) {
                button("Call 988", url: "tel:988", filled: support == .crisis,
                       hint: "Ends this call and calls the 988 Suicide and Crisis Lifeline")
                button("Text 988", url: "sms:988", filled: false,
                       hint: "Ends this call and opens Messages to text 988")
            }
            Text(support == .danger
                 ? "988 is free and confidential, 24/7."
                 : "988 is free and confidential, 24/7. In immediate danger? Call 911.")
                .cedTextStyle(.caption)
                .foregroundStyle(CEDColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.xl))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crisis support")
    }

    private func button(_ title: String, url: String, filled: Bool, hint: String) -> some View {
        Button { open(URL(string: url)!) } label: {
            Text(title)
                .cedTextStyle(.bodyBold)
                .foregroundStyle(filled ? CEDColor.cream : CEDColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(filled ? CEDColor.primary : CEDColor.card, in: RoundedRectangle(cornerRadius: CEDRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: CEDRadius.lg).strokeBorder(CEDColor.primary, lineWidth: 1.5))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityHint(hint)
    }
}

// MARK: - Entry point

/// The phone button that starts a call with Ced (replaces the old,
/// inactive microphone buttons on the Talk screens).
struct CallCedButton: View {
    var size: CGFloat = 44
    @State private var isCalling = false

    var body: some View {
        Button { isCalling = true } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(CEDColor.primary)
                .frame(width: size, height: size)
                .background(CEDColor.secondary, in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Call Ced")
        .accessibilityHint("Starts a voice call with Ced")
        .fullScreenCover(isPresented: $isCalling) {
            CallCedView()
        }
    }
}

#Preview {
    let _ = FontRegistrar.registerBundledFonts()
    CallCedView()
}
