import SwiftUI

struct ExtensionPermissionPromptView: View {
    @Environment(\.dismiss) private var dismiss
    let pending: PendingExtensionInstall
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.purple)
                    Text(pending.manifest.name)
                        .font(.title3.bold())
                    Text("Version \(pending.manifest.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    Text("This extension wants to:")
                        .font(.subheadline.weight(.semibold))
                    if pending.permissionRequests.isEmpty {
                        Text("Nothing — it requests no special permissions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pending.permissionRequests) { request in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(request.displayText)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                .padding(.horizontal)

                Spacer()

                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel) { onCancel(); dismiss() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Allow") { onAllow(); dismiss() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
