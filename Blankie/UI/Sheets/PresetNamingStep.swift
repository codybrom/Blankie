import SwiftUI

struct PresetNamingStep: View {
    @ObservedObject var presetManager: PresetManager
    @ObservedObject var audioManager: AudioManager

    @State private var suggestedName: String = ""
    @State private var customName: String = ""
    @State private var isGenerating: Bool = false
    @State private var aiAvailable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name your preset")
                .font(.title)
                .bold()

            Text("You can edit the name or try another suggestion.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Preset name", text: $customName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .accessibilityLabel("Preset name input field")

            HStack(spacing: 16) {
                if aiAvailable {
                    Button {
                        regenerateSuggestion()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .accessibilityLabel("Generating another name")
                        } else {
                            Label("Generate another", systemImage: "sparkles")
                                .accessibilityLabel("Generate another preset name")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }

                Button("Use this name") {
                    let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmed.isEmpty ? suggestedName : trimmed
                    if let currentPreset = presetManager.currentPreset {
                        presetManager.updatePreset(currentPreset, newName: finalName)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Use this preset name")
            }
        }
        .padding()
        .onAppear {
            aiAvailable = AIPresetNameGenerator.isAvailable
            Task {
                await generateInitialSuggestion()
            }
        }
    }

    private func generateInitialSuggestion() async {
        let selectedTitles = audioManager.sounds.filter { $0.isSelected }.map { $0.title }
        guard !selectedTitles.isEmpty else { return }
        isGenerating = true
        let suggestion = await AIPresetNameGenerator.generateName(from: selectedTitles, allowVariation: false)
        DispatchQueue.main.async {
            suggestedName = suggestion
            if customName.isEmpty {
                customName = suggestion
            }
            isGenerating = false
        }
    }

    private func regenerateSuggestion() {
        guard !isGenerating else { return }
        let selectedTitles = audioManager.sounds.filter { $0.isSelected }.map { $0.title }
        guard !selectedTitles.isEmpty else { return }

        isGenerating = true
        Task {
            let suggestion = await AIPresetNameGenerator.generateName(from: selectedTitles, allowVariation: true)
            DispatchQueue.main.async {
                suggestedName = suggestion
                customName = suggestion
                isGenerating = false
            }
        }
    }
}

#Preview("With Selected Sounds") {
    // Seed a few selected sounds for preview
    let audio = AudioManager.shared
    if audio.sounds.isEmpty == false {
        for i in 0 ..< min(3, audio.sounds.count) {
            audio.sounds[i].isSelected = true
        }
    }
    return PresetNamingStep(
        presetManager: PresetManager.shared,
        audioManager: audio
    )
}
