import SwiftUI

struct ContentView: View {
    @State private var selectedMood: String?
    @AppStorage("savedMood") private var savedMood = ""
    @AppStorage("savedAt") private var savedAt = 0.0

    private let moods = ["Happy", "Neutral", "Sad"]
    private let blue = Color(red: 0.35, green: 0.49, blue: 0.67)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Daily Check-In")
                .font(.largeTitle.bold())

            Text("How are you feeling today?")
                .font(.title2)

            ForEach(moods, id: \.self) { mood in
                Button {
                    selectedMood = mood
                } label: {
                    HStack {
                        Text(mood)
                        Spacer()
                        if selectedMood == mood {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .font(.headline)
                    .padding()
                    .background(
                        selectedMood == mood
                            ? blue.opacity(0.2)
                            : Color.white
                    )
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            Button {
                guard let selectedMood else { return }
                savedMood = selectedMood
                savedAt = Date().timeIntervalSince1970
            } label: {
                Text("Save Check-In")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedMood == nil)
            .opacity(selectedMood == nil ? 0.5 : 1)

            if !savedMood.isEmpty {
                Text("Saved! Your last check-in was \(savedMood.lowercased()).")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.95, blue: 0.92))
    }
}
