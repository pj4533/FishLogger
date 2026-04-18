import SwiftUI

/// Custom map annotation — a little wooden stake with a triangular pennant.
struct WoodenStake: View {
    var label: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let label {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.bark)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.ink.opacity(0.5), lineWidth: 1)
                    )
            }
            Rectangle()
                .fill(Color.bark)
                .frame(width: 3, height: 16)
                .overlay(
                    Rectangle()
                        .stroke(Color.ink.opacity(0.5), lineWidth: 0.5)
                )
            Image(systemName: "fish.fill")
                .font(.caption)
                .foregroundStyle(Color.sunset)
                .offset(y: -4)
        }
    }
}

#Preview {
    ZStack {
        Color.waterLight
        WoodenStake(label: "The Cove")
    }
    .frame(width: 200, height: 200)
}
