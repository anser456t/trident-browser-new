import SwiftUI

/// Create or edit a Space: name, accent color, and archive policy shortcut.
struct SpaceEditorView: View {
    @EnvironmentObject var browser: BrowserViewModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let space: Space?

    @State private var name: String = ""
    @State private var colorHex: String = AccentPreset.purple.hex
    @State private var symbolName: String = "square.stack"

    private let symbols = [
        "square.stack", "person.crop.circle", "briefcase", "graduationcap",
        "hammer", "gamecontroller", "paintbrush", "airplane",
        "house", "cart", "creditcard", "banknote",
        "book", "newspaper", "film", "music.note",
        "camera", "photo", "paperplane", "envelope",
        "message", "phone", "video", "mic",
        "heart", "star", "flag", "bell",
        "folder", "doc.text", "chart.bar", "calendar",
        "globe", "network", "cloud", "bolt",
        "leaf", "pawprint", "figure.run", "dumbbell",
        "cup.and.saucer", "fork.knife", "car", "bicycle",
        "moon", "sun.max", "sparkles", "flame",
        "wrench.and.screwdriver", "terminal", "cpu", "lock",
        "puzzlepiece", "gift", "tag", "bookmark"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Space") {
                    TextField("Name", text: $name)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(AccentPreset.allCases) { preset in
                            Circle()
                                .fill(preset.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: colorHex == preset.hex ? 2 : 0)
                                )
                                .onTapGesture { colorHex = preset.hex }
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(symbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(symbolName == symbol ? Color.white.opacity(0.2) : Color.clear)
                                )
                                .onTapGesture { symbolName = symbol }
                        }
                    }
                }

                if let space {
                    Section("Tabs") {
                        Picker("Archive Inactive Tabs", selection: $settings.archiveInterval) {
                            ForEach(ArchiveInterval.allCases) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                    }
                    Section {
                        if browser.spaces.count > 1 {
                            Button("Delete Space", role: .destructive) {
                                browser.deleteSpace(space)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(space == nil ? "New Space" : "Space Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(space == nil ? "Create" : "Done") {
                        commit()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let space {
                name = space.name
                colorHex = space.colorHex
                symbolName = space.symbolName
            }
        }
    }

    private func commit() {
        if let space {
            space.name = name
            space.colorHex = colorHex
            space.symbolName = symbolName
            try? browser.context.save()
        } else {
            browser.createSpace(name: name, colorHex: colorHex, symbolName: symbolName)
        }
    }
}
