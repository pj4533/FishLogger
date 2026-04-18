import SwiftUI

/// Tiny pill shown next to a field when its value came from an auto source
/// (e.g. photo EXIF, GPS). Helps the user spot and override when wanted.
struct SourceBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.moss)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.moss.opacity(0.18))
        )
    }
}

#Preview {
    SourceBadge(icon: "camera.fill", label: "from photo")
        .padding()
        .background(Color.paper)
}
