import SwiftUI

struct AutocompleteField: View {
    let label: String
    @Binding var text: String
    let suggestions: [String]
    var icon: String = "tag"

    @FocusState private var isFocused: Bool

    private var filtered: [String] {
        let list = AutocompleteService.filtered(suggestions, matching: text)
        return Array(list.prefix(8))
    }

    private var showDropdown: Bool {
        isFocused && !filtered.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            textField
            if showDropdown {
                dropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.18), value: isFocused)
        .animation(.snappy(duration: 0.18), value: filtered)
    }

    // MARK: - Subviews

    private var textField: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.inkFaded)
            TextField(label, text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.cozyBody)
                .submitLabel(.done)
                .onSubmit { isFocused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.inkFaded)
                }
                .buttonStyle(.plain)
            } else if !suggestions.isEmpty {
                Image(systemName: isFocused ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? Color.sunset : Color.bark.opacity(0.5),
                        lineWidth: isFocused ? 2 : 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private var dropdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element) { index, suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    highlightQuery: text
                ) {
                    text = suggestion
                    isFocused = false
                }
                if index < filtered.count - 1 {
                    Divider()
                        .background(Color.bark.opacity(0.15))
                        .padding(.horizontal, 12)
                }
            }
        }
        .background(Color.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: Color.ink.opacity(0.12), radius: 8, y: 3)
    }
}

// MARK: - Row

private struct SuggestionRow: View {
    let suggestion: String
    let highlightQuery: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(Color.inkFaded)
                highlightedText
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left")
                    .font(.caption2)
                    .foregroundStyle(Color.inkFaded.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(SuggestionRowStyle())
    }

    @ViewBuilder
    private var highlightedText: some View {
        let q = highlightQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty,
           let range = suggestion.range(of: q, options: .caseInsensitive) {
            let before = suggestion[suggestion.startIndex..<range.lowerBound]
            let hit    = suggestion[range]
            let after  = suggestion[range.upperBound..<suggestion.endIndex]
            (Text(String(before))
                .font(.cozyBody)
                .foregroundColor(Color.ink)
             + Text(String(hit))
                .font(.cozyBody.weight(.semibold))
                .foregroundColor(Color.sunset)
             + Text(String(after))
                .font(.cozyBody)
                .foregroundColor(Color.ink))
        } else {
            Text(suggestion)
                .font(.cozyBody)
                .foregroundStyle(Color.ink)
        }
    }
}

private struct SuggestionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.moss.opacity(0.25) : Color.clear)
    }
}
