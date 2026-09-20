import SwiftUI
import UIKit
import PhotosUI
import ImageIO

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var customColor: Color = .purple
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isSavingImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsGroup("Theme") {
                Picker("Appearance", selection: $settings.colorSchemePreference) {
                    ForEach(ColorSchemePreference.allCases) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            }

            settingsGroup("Theme Presets") {
                Text("One tap sets the accent color, background, and glass tint together. You can still fine-tune anything below afterward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(ThemePreset.all) { preset in
                        ThemePresetSwatch(preset: preset, isSelected: settings.lastAppliedThemePresetID == preset.id) {
                            preset.apply(to: settings)
                        }
                    }
                }
            }

            settingsGroup("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(AccentPreset.allCases) { preset in
                        Circle()
                            .fill(preset.color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.primary, lineWidth: settings.accentColorHex == preset.hex ? 2 : 0))
                            .onTapGesture { settings.accentColorHex = preset.hex }
                    }
                }
                ColorPicker("Custom Color", selection: $customColor)
                    .onChange(of: customColor) { _, newValue in
                        settings.accentColorHex = newValue.toHex()
                    }
            }

            settingsGroup("Background") {
                Picker("Style", selection: $settings.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.backgroundStyle {
                case .solid:
                    ColorPicker("Background Color", selection: Binding(
                        get: { Color(hex: settings.backgroundSolidHex) },
                        set: { settings.backgroundSolidHex = $0.toHex() }
                    ))
                case .gradient:
                    ColorPicker("Start Color", selection: Binding(
                        get: { Color(hex: settings.gradientStartHex) },
                        set: { settings.gradientStartHex = $0.toHex() }
                    ))
                    ColorPicker("End Color", selection: Binding(
                        get: { Color(hex: settings.gradientEndHex) },
                        set: { settings.gradientEndHex = $0.toHex() }
                    ))
                    VStack(alignment: .leading) {
                        Text("Direction: \(Int(settings.gradientAngleDegrees))°").font(.caption)
                        Slider(value: $settings.gradientAngleDegrees, in: 0...360)
                    }
                    VStack(alignment: .leading) {
                        Text("Intensity: \(Int(settings.gradientIntensity * 100))%").font(.caption)
                        Slider(value: $settings.gradientIntensity, in: 0.1...1.0)
                    }
                case .image:
                    VStack(alignment: .leading, spacing: 10) {
                        if let path = settings.customBackgroundImagePath,
                           let uiImage = BackgroundImageStore.load(path: path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .clipped()
                        }
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label(settings.customBackgroundImagePath == nil ? "Choose Photo" : "Change Photo", systemImage: "photo.on.rectangle")
                            }
                            if isSavingImage {
                                ProgressView().controlSize(.small)
                            }
                            if settings.customBackgroundImagePath != nil {
                                Button("Remove", role: .destructive) {
                                    removeBackgroundImage()
                                }
                            }
                        }

                        Picker("Fill", selection: $settings.backgroundImageFillMode) {
                            ForEach(BackgroundFillMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading) {
                            Text("Blur: \(Int(settings.backgroundImageBlur))pt").font(.caption)
                            Slider(value: $settings.backgroundImageBlur, in: 0...40)
                        }
                        VStack(alignment: .leading) {
                            Text("Transparency: \(Int(settings.backgroundImageOpacity * 100))%").font(.caption)
                            Slider(value: $settings.backgroundImageOpacity, in: 0.1...1.0)
                        }

                        Text("The image fills the screen behind translucent sidebar and glass panels. \"Fit\" letterboxes instead of cropping to match your screen's aspect ratio.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        guard let newItem else { return }
                        isSavingImage = true
                        Task {
                            defer { isSavingImage = false }
                            guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                            if let path = saveBackgroundImage(data) {
                                await MainActor.run {
                                    BackgroundImageStore.invalidate(path: path)
                                    settings.customBackgroundImagePath = path
                                }
                            }
                        }
                    }
                case .defaultStyle:
                    Text("A soft accent-tinted gradient that adapts to your accent color.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Background Blur").foregroundStyle(.secondary)
                    Slider(value: $settings.backgroundBlurAmount, in: 0...40)
                }
                Text("Softens the whole background — this is what shows behind the sidebar and around the web page card in the floating window layout, regardless of which style is selected above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AppearancePreview()
        }
        .onAppear { customColor = Color(hex: settings.accentColorHex) }
    }

    /// Cancels any in-flight photo import, drops the cached decode, deletes the
    /// file, and only then clears the setting — in that order, so nothing else
    /// on screen can still be pointing at the file while it's removed. Doing
    /// this out of order (or leaving a huge undecoded photo behind) is what let
    /// a stray decode of a deleted/huge file bring the app down.
    private func removeBackgroundImage() {
        selectedPhotoItem = nil
        if let path = settings.customBackgroundImagePath {
            BackgroundImageStore.invalidate(path: path)
            try? FileManager.default.removeItem(atPath: path)
        }
        settings.customBackgroundImagePath = nil
    }
}

/// Persists a picked photo's data to the app's own Documents folder and
/// returns the on-disk path AppSettings should store. The image is downsampled
/// before writing — full-resolution photos (12+ MP HEIC/ProRAW) decoded
/// repeatedly as a full-screen background were the root cause of the
/// out-of-memory crash when removing/replacing a custom background.
private func saveBackgroundImage(_ data: Data) -> String? {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Backgrounds", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("background.jpg")

    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let maxDimension: CGFloat = 2400
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let downsized = UIImage(cgImage: cgImage)
    guard let jpegData = downsized.jpegData(compressionQuality: 0.85) else { return nil }

    do {
        // Remove any previous file first so a stale, differently-sized image
        // is never briefly readable at the same path mid-write.
        try? FileManager.default.removeItem(at: url)
        try jpegData.write(to: url, options: .atomic)
        return url.path
    } catch {
        return nil
    }
}

/// A one-tap combination of accent color + background + glass tint, so
/// changing the whole look doesn't mean visiting five different sliders.
/// Applying a preset still just writes plain `AppSettings` values — nothing
/// here is a distinct "mode", so every other control keeps working exactly
/// as before and can be nudged afterward without losing anything.
struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let accentHex: String
    let gradientStartHex: String
    let gradientEndHex: String
    let angle: Double
    let sidebarTransparency: Double
    let sidebarBlur: Double

    var swatchGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: gradientStartHex), Color(hex: gradientEndHex)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func apply(to settings: AppSettings) {
        settings.accentColorHex = accentHex
        settings.backgroundStyle = .gradient
        settings.gradientStartHex = gradientStartHex
        settings.gradientEndHex = gradientEndHex
        settings.gradientAngleDegrees = angle
        settings.gradientIntensity = 0.6
        settings.sidebarTransparency = sidebarTransparency
        settings.sidebarBlur = sidebarBlur
        settings.lastAppliedThemePresetID = id
    }

    static let all: [ThemePreset] = [
        ThemePreset(id: "midnight", name: "Midnight", accentHex: "#A78BFA", gradientStartHex: "#1E1B4B", gradientEndHex: "#0F0A24", angle: 135, sidebarTransparency: 0.55, sidebarBlur: 24),
        ThemePreset(id: "sunset", name: "Sunset", accentHex: "#FB923C", gradientStartHex: "#7C2D12", gradientEndHex: "#831843", angle: 140, sidebarTransparency: 0.5, sidebarBlur: 22),
        ThemePreset(id: "ocean", name: "Ocean", accentHex: "#38BDF8", gradientStartHex: "#0C4A6E", gradientEndHex: "#082F49", angle: 130, sidebarTransparency: 0.55, sidebarBlur: 26),
        ThemePreset(id: "forest", name: "Forest", accentHex: "#4ADE80", gradientStartHex: "#052E16", gradientEndHex: "#14532D", angle: 145, sidebarTransparency: 0.55, sidebarBlur: 24),
        ThemePreset(id: "rose", name: "Rose", accentHex: "#F472B6", gradientStartHex: "#500724", gradientEndHex: "#831843", angle: 135, sidebarTransparency: 0.5, sidebarBlur: 22),
        ThemePreset(id: "mono", name: "Mono", accentHex: "#E5E7EB", gradientStartHex: "#111827", gradientEndHex: "#000000", angle: 135, sidebarTransparency: 0.6, sidebarBlur: 20),
        ThemePreset(id: "cyber", name: "Cyber", accentHex: "#39FF14", gradientStartHex: "#0A0A0A", gradientEndHex: "#062E1F", angle: 120, sidebarTransparency: 0.45, sidebarBlur: 18),
        ThemePreset(id: "sand", name: "Sand", accentHex: "#D6A15C", gradientStartHex: "#3A2E22", gradientEndHex: "#1C1712", angle: 140, sidebarTransparency: 0.55, sidebarBlur: 24)
    ]
}

private struct ThemePresetSwatch: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(preset.swatchGradient)
                        .frame(height: 48)
                    Circle()
                        .fill(Color(hex: preset.accentHex))
                        .frame(width: 12, height: 12)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
                )
                Text(preset.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }
}

private struct AppearancePreview: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREVIEW").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ZStack {
                AppBackgroundView()
                HStack {
                    GlassPanel(cornerRadius: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Circle().fill(settings.accentColor).frame(width: 10, height: 10)
                            Text("Sidebar").font(.caption).foregroundStyle(.white)
                        }
                        .padding(12)
                    }
                    .frame(width: 100)
                    Spacer()
                }
                .padding(12)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
