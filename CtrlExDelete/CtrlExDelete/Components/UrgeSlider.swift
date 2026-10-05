import SwiftUI

/// The 1–10 slider from the check-in screen: a thin rounded track that fills
/// with dark blue, and a round thumb with a white ring and soft shadow.
struct UrgeSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...10
    /// Called whenever the user moves the slider.
    var onChange: () -> Void = {}

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CEDColor.border)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(CEDColor.primary)
                    .frame(width: fraction * width, height: trackHeight)
                Circle()
                    .fill(CEDColor.primary)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: CEDColor.primary.opacity(0.4), radius: 4, y: 2)
                    .offset(x: fraction * (width - thumbSize))
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        setValue(forX: drag.location.x, width: width)
                    }
            )
        }
        .frame(height: thumbSize)
        // Like the web slider, only the 6pt track takes up layout space;
        // the thumb overlaps the labels above and below it.
        .padding(.vertical, -(thumbSize - trackHeight) / 2)
        .accessibilityElement()
        .accessibilityLabel("Urge to contact them")
        .accessibilityValue("\(value) out of \(range.upperBound)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: update(to: value + 1)
            case .decrement: update(to: value - 1)
            @unknown default: break
            }
        }
    }

    private func setValue(forX x: CGFloat, width: CGFloat) {
        let usable = max(width - thumbSize, 1)
        let fraction = min(max((x - thumbSize / 2) / usable, 0), 1)
        let steps = CGFloat(range.upperBound - range.lowerBound)
        update(to: range.lowerBound + Int((fraction * steps).rounded()))
    }

    private func update(to newValue: Int) {
        value = min(max(newValue, range.lowerBound), range.upperBound)
        onChange()
    }
}
