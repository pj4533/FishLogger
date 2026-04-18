import SwiftUI

struct AutocompleteField: View {
    let label: String
    @Binding var text: String
    let suggestions: [String]
    var icon: String = "tag"

    @State private var focused: Bool = false
    @FocusState private var fieldFocus: Bool

    private var filtered: [String] {
        AutocompleteService.filtered(suggestions, matching: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.inkFaded)
                TextField(label, text: $text)
                    .focused($fieldFocus)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.cozyBody)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if fieldFocus && !filtered.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filtered.prefix(8), id: \.self) { suggestion in
                            Button {
                                text = suggestion
                                fieldFocus = false
                            } label: {
                                Text(suggestion)
                                    .font(.cozyCaption)
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.moss.opacity(0.3))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
