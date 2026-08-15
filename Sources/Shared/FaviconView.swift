import SwiftUI

/// Lightweight favicon loader with graceful fallback to a monogram glyph.
struct FaviconView: View {
    let host: String
    var size: CGFloat = 16

    private var faviconURL: URL? {
        guard !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(host)")
    }

    var body: some View {
        Group {
            if let url = faviconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(Color.white.opacity(0.12))
            .overlay(
                Text(String(host.first ?? "?").uppercased())
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }
}
