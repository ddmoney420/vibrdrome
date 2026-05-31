#if os(macOS)
import SwiftUI

struct SmartPlaylistEditorView: View {
    enum Mode {
        case create
        case edit(playlistId: String)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onSave: (() async -> Void)?

    @State private var name: String
    @State private var ruleSet: FilterRuleSet
    @State private var sortField: SortOption = .none
    @State private var sortAscending = true
    @State private var limitEnabled = false
    @State private var limit = 25
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSave = false

    init(mode: Mode, initialName: String = "", initialRules: NSPCriteria? = nil, onSave: (() async -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        if let criteria = initialRules {
            self._ruleSet = State(initialValue: FilterRuleSet(from: criteria))
            self._sortField = State(initialValue: SortOption(nspName: criteria.sort))
            self._sortAscending = State(initialValue: criteria.order != "desc")
            if let lim = criteria.limit {
                self._limitEnabled = State(initialValue: true)
                self._limit = State(initialValue: lim)
            }
        } else {
            self._ruleSet = State(initialValue: FilterRuleSet())
        }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }
    private var isCreating: Bool { if case .create = mode { return true }; return false }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("Name", text: $name, prompt: Text("My Smart Playlist"))
                }
                Section("Rules") {
                    RuleEditorContent(ruleSet: $ruleSet)
                }
                Section("Sort & Limit") {
                    sortSection
                }
                if let msg = errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isCreating ? "New Smart Playlist" : "Edit Smart Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if didSave {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(isCreating ? "Create" : "Save") { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }

    // MARK: - Sort & Limit section

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Sort by")
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Picker("", selection: $sortField) {
                    ForEach(SortOption.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                if sortField != .none {
                    Picker("", selection: $sortAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            HStack(spacing: 8) {
                Toggle("Limit to", isOn: $limitEnabled)
                    .toggleStyle(.checkbox)
                    .frame(width: 80, alignment: .trailing)
                if limitEnabled {
                    TextField("", value: $limit, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("songs")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Save

    private func save() {
        guard let ndClient = appState.navidromeClient, canSave else {
            errorMessage = "Navidrome connection not available"
            return
        }
        isSaving = true
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let criteria = NSPCriteria(
            from: ruleSet,
            sort: sortField == .none ? nil : sortField.nspName,
            order: (sortField != .none && !sortAscending) ? "desc" : nil,
            limit: limitEnabled ? limit : nil
        )
        Task {
            do {
                switch mode {
                case .create:
                    try await ndClient.createSmartPlaylist(name: trimmedName, comment: "", rules: criteria)
                case .edit(let playlistId):
                    try await ndClient.updateSmartPlaylist(id: playlistId, name: trimmedName, rules: criteria)
                }
                await MainActor.run { isSaving = false; didSave = true }
                await onSave?()
                try? await Task.sleep(for: .seconds(0.8))
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Sort options

private enum SortOption: String, CaseIterable {
    case none
    case title, artist, album, genre, year, rating, playCount, lastPlayed
    case random, dateAdded, bpm, duration

    var label: String {
        switch self {
        case .none:       return "None (server default)"
        case .title:      return "Title"
        case .artist:     return "Artist"
        case .album:      return "Album"
        case .genre:      return "Genre"
        case .year:       return "Year"
        case .rating:     return "Rating"
        case .playCount:  return "Play Count"
        case .lastPlayed: return "Last Played"
        case .random:     return "Random"
        case .dateAdded:  return "Date Added"
        case .bpm:        return "BPM"
        case .duration:   return "Duration"
        }
    }

    var nspName: String? {
        switch self {
        case .none:       return nil
        case .title:      return "title"
        case .artist:     return "artist"
        case .album:      return "album"
        case .genre:      return "genre"
        case .year:       return "year"
        case .rating:     return "rating"
        case .playCount:  return "playcount"
        case .lastPlayed: return "lastplayed"
        case .random:     return "random"
        case .dateAdded:  return "dateadded"
        case .bpm:        return "bpm"
        case .duration:   return "duration"
        }
    }

    init(nspName: String?) {
        guard let name = nspName else { self = .none; return }
        self = SortOption.allCases.first { $0.nspName == name } ?? .none
    }
}

// MARK: - Inline rule editor

private struct RuleEditorContent: View {
    @Binding var ruleSet: FilterRuleSet
    let allowedFields = FilterField.smartPlaylistFields

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ruleSet.rules.count > 1 {
                combinatorPicker
            }

            if ruleSet.rules.isEmpty {
                Text("No rules yet — click + to add one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach($ruleSet.rules) { $rule in
                    RuleRow(rule: $rule, allowedFields: allowedFields) {
                        ruleSet.rules.removeAll { $0.id == rule.id }
                    }
                }
            }

            Button {
                let field = allowedFields.first ?? .title
                let op = FilterOperator.allowed(for: field.kind).first(where: \.nspSupported) ?? .contains
                ruleSet.rules.append(FilterRule(field: field, operator: op, value: .defaultValue(for: field.kind)))
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }

    private var combinatorPicker: some View {
        HStack(spacing: 4) {
            Text("Match")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $ruleSet.combinator) {
                Text("ALL rules").tag(FilterRuleSet.Combinator.all)
                Text("ANY rule").tag(FilterRuleSet.Combinator.any)
            }
            .pickerStyle(.menu)
            .controlSize(.mini)
            .labelsHidden()
            .frame(width: 100)
        }
    }
}

// MARK: - Rule row

private struct RuleRow: View {
    @Binding var rule: FilterRule
    let allowedFields: [FilterField]
    let onRemove: () -> Void

    @State private var draftText = ""
    @State private var draftNumber = 0
    @State private var draftRangeLo = 0
    @State private var draftRangeHi = 0
    @State private var draftDate = Date()

    var body: some View {
        HStack(spacing: 6) {
            fieldPicker
            operatorPicker
            valueInput
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove rule")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // NSP-supported operators only — drops matchesRegex, isGreaterOrEqual, isLessOrEqual.
    private func nspOperators(for kind: FilterField.FieldKind) -> [FilterOperator] {
        FilterOperator.allowed(for: kind).filter { $0.nspSupported }
    }

    private var fieldPicker: some View {
        Picker("", selection: $rule.field) {
            ForEach(allowedFields, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .labelsHidden()
        .frame(width: 130)
        .onChange(of: rule.field) { _, newField in
            let ops = nspOperators(for: newField.kind)
            if !ops.contains(rule.operator) { rule.operator = ops[0] }
            rule.value = .defaultValue(for: newField.kind)
            syncDrafts()
        }
    }

    private var operatorPicker: some View {
        let ops = nspOperators(for: rule.field.kind)
        return Picker("", selection: $rule.operator) {
            ForEach(ops, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .labelsHidden()
        .frame(width: 120)
        .onChange(of: rule.operator) { _, newOp in
            if newOp == .isBetween, case .number(let n) = rule.value {
                rule.value = .range(n, n); draftRangeLo = n; draftRangeHi = n
            } else if newOp != .isBetween, case .range(let lo, _) = rule.value {
                rule.value = .number(lo); draftNumber = lo
            }
            // Switching between days-count and absolute-date operators needs a value type change.
            if newOp == .before || newOp == .after {
                rule.value = .text(Self.dateFormatter.string(from: draftDate))
            } else if newOp == .inTheLast || newOp == .notInTheLast {
                if case .text = rule.value { rule.value = .number(draftNumber) }
            }
        }
    }

    @ViewBuilder
    private var valueInput: some View {
        switch rule.field.kind {
        case .text:     textInput
        case .numeric:  numericInput
        case .days:     daysInput
        case .boolean:  boolInput
        case .playlist: textInput
        }
    }

    private var textInput: some View {
        TextField("value…", text: $draftText)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(minWidth: 100)
            .onChange(of: draftText) { _, v in rule.value = .text(v) }
            .onAppear { syncDrafts() }
    }

    @ViewBuilder
    private var numericInput: some View {
        if rule.operator == .isBetween {
            HStack(spacing: 4) {
                TextField("from", value: $draftRangeLo, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 55)
                    .onAppear { syncDrafts() }
                    .onChange(of: draftRangeLo) { _, lo in rule.value = .range(lo, draftRangeHi) }
                Text("–").foregroundStyle(.secondary)
                TextField("to", value: $draftRangeHi, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 55)
                    .onChange(of: draftRangeHi) { _, hi in rule.value = .range(draftRangeLo, hi) }
            }
        } else {
            TextField("0", value: $draftNumber, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 80)
                .onAppear { syncDrafts() }
                .onChange(of: draftNumber) { _, n in rule.value = .number(n) }
        }
    }

    @ViewBuilder
    private var daysInput: some View {
        if rule.operator == .before || rule.operator == .after {
            // Absolute date picker — value stored as "YYYY-MM-DD" text.
            DatePicker("", selection: $draftDate, displayedComponents: .date)
                .labelsHidden()
                .controlSize(.small)
                .onAppear { syncDrafts() }
                .onChange(of: draftDate) { _, d in
                    rule.value = .text(Self.dateFormatter.string(from: d))
                }
        } else {
            // Relative days count.
            HStack(spacing: 4) {
                TextField("30", value: $draftNumber, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 60)
                    .onAppear { syncDrafts() }
                    .onChange(of: draftNumber) { _, n in rule.value = .number(n) }
                Text("days").foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    private var boolInput: some View {
        let binding = Binding<Bool>(
            get: { if case .boolean(let b) = rule.value { return b }; return true },
            set: { rule.value = .boolean($0) }
        )
        return Picker("", selection: binding) {
            Text("Yes").tag(true)
            Text("No").tag(false)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .frame(width: 90)
    }

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private func syncDrafts() {
        switch rule.value {
        case .text(let s):
            if let date = Self.dateFormatter.date(from: s) {
                draftDate = date
            } else {
                draftText = s
            }
        case .number(let n):  draftNumber = n
        case .range(let lo, let hi): draftRangeLo = lo; draftRangeHi = hi
        case .boolean: break
        }
    }
}
#endif
