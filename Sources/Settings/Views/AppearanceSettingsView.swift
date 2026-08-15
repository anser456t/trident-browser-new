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
