import SwiftUI

struct WeightBadge: View {
    let weight: Double
    let isMeasured: Bool

    private var weightText: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: weight)) ?? "\(weight)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "scalemass.fill")
                .font(.caption)
            Text("\(weightText) lb")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Image(systemName: isMeasured ? "ruler.fill" : "questionmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(isMeasured ? Color.moss : Color.sunset)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.paper)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.bark.opacity(0.6), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(weightText) pounds, \(isMeasured ? "measured" : "guessed")")
    }
}

#Preview {
    VStack(spacing: 12) {
        WeightBadge(weight: 4.2, isMeasured: true)
        WeightBadge(weight: 2.8, isMeasured: false)
    }
    .padding()
    .background(Color.paper)
}
