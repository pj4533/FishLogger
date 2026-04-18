import SwiftUI

struct CozyCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.paperDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.bark, lineWidth: 2)
            )
            .shadow(color: Color.ink.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}

#Preview {
    CozyCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nice catch!")
                .font(.species)
                .foregroundStyle(Color.ink)
            Text("Largemouth Bass")
                .font(.cozyBody)
                .foregroundStyle(Color.inkFaded)
        }
    }
    .padding()
    .background(Color.paper)
}
