import SwiftUI

/// A small speaker icon that only appears while a tab's page has audio (or
/// video) actively playing — sized to match the existing tab-row close
/// button rather than standing out. Takes the controller as its own
/// `@ObservedObject` (instead of the parent reading `.isPlayingAudio`
/// directly) so playback starting/stopping updates it live instead of only
/// on the next unrelated re-render.
struct AudioIndicatorBadge: View {
    @ObservedObject var controller: WebViewController
    var diameter: CGFloat = 16

    var body: some View {
        if controller.isPlayingAudio {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: diameter * 0.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
    }
}
