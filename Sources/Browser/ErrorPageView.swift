import SwiftUI

struct ErrorPageView: View {
    let error: BrowserLoadError
    let onRetry: () -> Void

    private var icon: String {
        switch error.kind {
        case .offline: return "wifi.slash"
        case .dns: return "questionmark.diamond"
        case .ssl: return "lock.trianglebadge.exclamationmark"
        case .generic: return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch error.kind {
        case .offline: return "You're Offline"
        case .dns: return "Can't Find Server"
        case .ssl: return "Connection Not Private"
        case .generic: return "Page Couldn't Load"
        }
    }

    private var message: String {
        switch error.kind {
        case .offline: return "Check your network connection and try again. Trident will keep this tab ready to reload."
        case .dns: return "The address \(error.failingURL?.host ?? "") couldn't be resolved. Check the URL and try again."
        case .ssl: return "This site's security certificate could not be verified. Proceed only if you trust this website."
        case .generic: return error.message
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.18))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0B0B14"))
    }
}
