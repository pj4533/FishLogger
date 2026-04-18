import SwiftUI

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.sunset)
            Text(title)
                .font(.diaryHeader)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.cozyBody)
                .foregroundStyle(Color.inkFaded)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}

#Preview {
    EmptyState(
        symbol: "fish",
        title: "No catches yet",
        message: "Cast a line and log your first catch!"
    )
}
