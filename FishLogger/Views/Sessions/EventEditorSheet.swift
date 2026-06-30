import SwiftUI
import SwiftData

/// Add or edit a single timeline `SessionEvent` (setup change, sub-spot, bite,
/// or note) by hand — the manual counterpart to the voice assistant's tools.
/// Edits are held in local state and committed on Save (so Cancel discards),
/// matching the canonical sheet shell used by `AddCatchSheet`.
struct EventEditorSheet: View {
    enum Mode {
        case add(SessionEventKind)
        case edit(SessionEvent)

        var kind: SessionEventKind {
            switch self {
            case let .add(kind):  return kind
            case let .edit(event): return event.kind
            }
        }

        var isEdit: Bool { if case .edit = self { return true }; return false }
    }

    let session: Session
    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var timestamp = Date.now
    // setup
    @State private var rod = ""
    @State private var reel = ""
    @State private var line = ""
    @State private var lure = ""
    @State private var color = ""
    @State private var technique = ""
    // sub-spot
    @State private var subSpot = ""
    // bite
    @State private var outcome: BiteOutcome = .bite
    @State private var biteDetail = ""
    // note
    @State private var noteText = ""

    @State private var didLoad = false

    private var baitSuggestions: [String] {
        AutocompleteService.suggestions(for: .bait, context: context)
    }
    private var rodSuggestions: [String] {
        AutocompleteService.suggestions(for: .rod, context: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    whenCard
                    fieldsCard
                    if mode.isEdit { deleteCard }
                    saveButton.padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .onAppear(perform: loadOnce)
        }
    }

    private var title: String {
        (mode.isEdit ? "Edit " : "Add ") + kindName
    }

    private var kindName: String {
        switch mode.kind {
        case .setupChange:  return "setup change"
        case .subSpotChange: return "sub-spot"
        case .bite:         return "bite"
        case .note:         return "note"
        }
    }

    // MARK: - Cards

    private var whenCard: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHEN").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                DatePicker("", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.sunset)
            }
        }
    }

    @ViewBuilder
    private var fieldsCard: some View {
        switch mode.kind {
        case .setupChange:  setupCard
        case .subSpotChange: subSpotCard
        case .bite:         biteCard
        case .note:         noteCard
        }
    }

    private var setupCard: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("SETUP").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                labeledField("ROD", $rod, suggestions: rodSuggestions, icon: "figure.fishing")
                labeledField("REEL", $reel, icon: "circle.circle")
                labeledField("LINE", $line, icon: "scribble")
                labeledField("LURE / BAIT", $lure, suggestions: baitSuggestions, icon: "ladybug.fill")
                labeledField("COLOR", $color, icon: "paintpalette")
                labeledField("TECHNIQUE", $technique, icon: "figure.fishing")
                Text("The full setup as it stands at this point — every field, not just what changed.")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
            }
        }
    }

    private var subSpotCard: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("SUB-SPOT").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                AutocompleteField(label: "e.g. by the dam, north lily pads",
                                  text: $subSpot, suggestions: [], icon: "mappin")
            }
        }
    }

    private var biteCard: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHAT HAPPENED").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                Picker("", selection: $outcome) {
                    ForEach(BiteOutcome.allCases, id: \.self) { o in
                        Text(o.display).tag(o)
                    }
                }
                .pickerStyle(.segmented)

                Text("DETAIL").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                AutocompleteField(label: "Optional — what you saw",
                                  text: $biteDetail, suggestions: [], icon: "text.alignleft")
            }
        }
    }

    private var noteCard: some View {
        CozyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("NOTE").font(.fieldLabel).foregroundStyle(Color.inkFaded)
                TextEditor(text: $noteText)
                    .font(.cozyBody)
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.bark.opacity(0.4), lineWidth: 1.5)
                    )
            }
        }
    }

    private var deleteCard: some View {
        Button(role: .destructive) {
            if case let .edit(event) = mode {
                SessionEventLogger.deleteEvent(event, from: session, context: context)
                try? context.save()
            }
            dismiss()
        } label: {
            Label("Delete this event", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(mode.isEdit ? "Save changes" : "Add to timeline")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule(style: .continuous).fill(canSave ? Color.sunset : Color.sunset.opacity(0.4)))
        }
        .disabled(!canSave)
    }

    private var canSave: Bool {
        switch mode.kind {
        case .setupChange:  return !resolvedSetup.isEmpty
        case .subSpotChange: return !subSpot.trimmed.isEmpty
        case .bite:         return true
        case .note:         return !noteText.trimmed.isEmpty
        }
    }

    @ViewBuilder
    private func labeledField(_ label: String, _ text: Binding<String>,
                              suggestions: [String] = [], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.fieldLabel).foregroundStyle(Color.inkFaded)
            AutocompleteField(label: label.capitalized, text: text,
                              suggestions: suggestions, icon: icon)
        }
    }

    // MARK: - State

    private var resolvedSetup: Setup {
        Setup(
            rod: rod.trimmed.nilIfBlank,
            reel: reel.trimmed.nilIfBlank,
            line: line.trimmed.nilIfBlank,
            lure: lure.trimmed.nilIfBlank,
            color: color.trimmed.nilIfBlank,
            technique: technique.trimmed.nilIfBlank
        )
    }

    /// Seeds local state once. In edit mode from the event; in add mode the time
    /// defaults to now and a setup change prefills from the session's current
    /// resolved setup (so it's a full snapshot the angler tweaks, not a delta).
    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case let .edit(event):
            timestamp = event.timestamp
            switch event.kind {
            case .setupChange:
                let s = event.setupSnapshot ?? Setup()
                rod = s.rod ?? ""; reel = s.reel ?? ""; line = s.line ?? ""
                lure = s.lure ?? ""; color = s.color ?? ""; technique = s.technique ?? ""
            case .subSpotChange:
                subSpot = event.subSpot ?? ""
            case .bite:
                outcome = event.outcome ?? .bite
                biteDetail = event.detail ?? ""
            case .note:
                noteText = event.detail ?? ""
            }
        case let .add(kind):
            timestamp = .now
            if kind == .setupChange {
                let s = session.currentSetup
                rod = s.rod ?? ""; reel = s.reel ?? ""; line = s.line ?? ""
                lure = s.lure ?? ""; color = s.color ?? ""; technique = s.technique ?? ""
            }
        }
    }

    private func save() {
        switch mode {
        case let .edit(event):
            event.timestamp = timestamp
            switch event.kind {
            case .setupChange:
                event.setupSnapshot = resolvedSetup
                SessionEventLogger.recomputeLiveState(for: session)
            case .subSpotChange:
                event.subSpot = subSpot.trimmed
                SessionEventLogger.recomputeLiveState(for: session)
            case .bite:
                event.outcomeRaw = outcome.rawValue
                event.detail = biteDetail.trimmed.nilIfBlank
            case .note:
                event.detail = noteText.trimmed
            }

        case let .add(kind):
            let event: SessionEvent
            switch kind {
            case .setupChange:
                event = SessionEvent(timestamp: timestamp, kind: .setupChange,
                                     session: session, setupSnapshot: resolvedSetup)
            case .subSpotChange:
                event = SessionEvent(timestamp: timestamp, kind: .subSpotChange,
                                     session: session, subSpot: subSpot.trimmed)
            case .bite:
                event = SessionEvent(timestamp: timestamp, kind: .bite, session: session,
                                     setupSnapshot: session.currentSetup.isEmpty ? nil : session.currentSetup,
                                     subSpot: session.currentSubSpot.isEmpty ? nil : session.currentSubSpot,
                                     outcome: outcome, detail: biteDetail.trimmed.nilIfBlank)
            case .note:
                event = SessionEvent(timestamp: timestamp, kind: .note,
                                     session: session, detail: noteText.trimmed)
            }
            context.insert(event)
            if kind == .setupChange || kind == .subSpotChange {
                SessionEventLogger.recomputeLiveState(for: session)
            }
        }

        try? context.save()
        dismiss()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { isEmpty ? nil : self }
}
