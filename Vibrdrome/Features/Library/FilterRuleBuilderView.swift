#if os(macOS)
import SwiftUI

/// Expandable "Advanced Filters" section rendered inside LibraryFilterSidebarView.
/// Lets the user compose operator-based rules (including regex) targeting diverse metadata fields.
struct FilterRuleBuilderView: View {
    @Binding var ruleSet: FilterRuleSet
    let allowedFields: [FilterField]
    /// AppStorage key for persisting the expanded state across sessions.
    let expandedKey: String

    @AppStorage private var isExpanded: Bool
    @State private var showSaveSheet = false

    init(ruleSet: Binding<FilterRuleSet>, allowedFields: [FilterField], expandedKey: String) {
        self._ruleSet = ruleSet
        self.allowedFields = allowedFields
        self.expandedKey = expandedKey
        self._isExpanded = AppStorage(wrappedValue: false, expandedKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            expanderHeader
            if isExpanded {
                builderContent
                    .padding(.top, 8)
            }
        }
        .onChange(of: ruleSet.rules.count) { oldCount, newCount in
            if oldCount == 0 && newCount == 1 {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded = true }
            } else if newCount == 0 {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
            }
        }
    }

    // MARK: - Expander Header

    private var expanderHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Advanced Filters")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                let activeCount = ruleSet.rules.filter { !$0.isEffectivelyEmpty }.count
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Builder Content

    private var builderContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ruleSet.rules.count > 1 {
                combinatorPicker
            }

            if ruleSet.rules.isEmpty {
                Text("No rules yet — click + to add one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                ForEach($ruleSet.rules) { $rule in
                    RuleRowView(rule: $rule, allowedFields: allowedFields) {
                        ruleSet.rules.removeAll { $0.id == rule.id }
                    }
                }
            }

            addRuleButton

            if !ruleSet.isEmpty {
                Divider().padding(.vertical, 4)
                saveAsSmartPlaylistButton
            }
        }
        .padding(.horizontal, 2)
        .sheet(isPresented: $showSaveSheet) {
            SaveSmartPlaylistSheet(ruleSet: ruleSet)
        }
    }

    // MARK: - Combinator Picker

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
            .frame(maxWidth: 110)
        }
    }

    // MARK: - Save as Smart Playlist

    private var saveAsSmartPlaylistButton: some View {
        Button {
            showSaveSheet = true
        } label: {
            Label("Save as Smart Playlist…", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help("Save these filter rules as a Navidrome Smart Playlist")
    }

    // MARK: - Add Rule Button

    private var addRuleButton: some View {
        Button {
            let defaultField = allowedFields.first ?? .title
            let defaultOp = FilterOperator.allowed(for: defaultField.kind).first ?? .contains
            ruleSet.rules.append(
                FilterRule(field: defaultField, operator: defaultOp, value: .defaultValue(for: defaultField.kind))
            )
        } label: {
            Label("Add Rule", systemImage: "plus.circle")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Individual Rule Row

private struct RuleRowView: View {
    @Binding var rule: FilterRule
    let allowedFields: [FilterField]
    let onRemove: () -> Void

    /// Local draft buffers — updated every keystroke, committed to rule.value after debounce.
    @State private var draftText: String = ""
    @State private var draftNumber: Int = 0
    @State private var draftRangeLo: Int = 0
    @State private var draftRangeHi: Int = 0
    @State private var debounceTask: Task<Void, Never>?
    /// Non-nil means the regex pattern is currently invalid.
    @State private var regexError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                fieldPicker
                operatorPicker
                Spacer()
                removeButton
            }
            valuePicker
            if let err = regexError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Pickers

    private var fieldPicker: some View {
        Picker("", selection: $rule.field) {
            ForEach(allowedFields, id: \.self) { field in
                Text(field.displayName).tag(field)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.mini)
        .labelsHidden()
        .onChange(of: rule.field) { _, newField in
            debounceTask?.cancel()
            let allowedOps = FilterOperator.allowed(for: newField.kind)
            if !allowedOps.contains(rule.operator) {
                rule.operator = allowedOps[0]
            }
            rule.value = .defaultValue(for: newField.kind)
            regexError = nil
            syncDraftsFromRule()
        }
    }

    private var operatorPicker: some View {
        let ops = FilterOperator.allowed(for: rule.field.kind)
        return Picker("", selection: $rule.operator) {
            ForEach(ops, id: \.self) { op in
                Text(op.displayName).tag(op)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.mini)
        .labelsHidden()
        .onChange(of: rule.operator) { _, newOp in
            if newOp == .isBetween, case .number(let n) = rule.value {
                rule.value = .range(n, n)
                draftRangeLo = n; draftRangeHi = n
            } else if newOp != .isBetween, case .range(let lo, _) = rule.value {
                rule.value = .number(lo)
                draftNumber = lo
            }
            if newOp != .matchesRegex { regexError = nil }
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove rule")
    }

    // MARK: Value Input

    @ViewBuilder
    private var valuePicker: some View {
        switch rule.field.kind {
        case .text:    textValueInput
        case .numeric: numericValueInput
        case .days:    daysValueInput
        case .boolean: booleanValueInput
        case .playlist: textValueInput
        }
    }

    // MARK: Text Input

    @ViewBuilder
    private var textValueInput: some View {
        HStack(spacing: 4) {
            TextField(rule.operator == .matchesRegex ? "/pattern/flags or pattern…" : "value…", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: draftText) { _, newText in scheduleCommit { .text(newText) }
                    if rule.operator == .matchesRegex { scheduleRegexValidation(newText) }
                }
                .onAppear { syncDraftsFromRule() }
            if rule.operator == .matchesRegex {
                Image(systemName: regexError == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(regexError == nil ? Color.green : Color.red)
                    .opacity(draftText.isEmpty ? 0 : 1)
            }
        }
    }

    // MARK: Numeric Inputs

    @ViewBuilder
    private var numericValueInput: some View {
        if rule.operator == .isBetween {
            rangeInput
        } else {
            singleNumberInput
        }
    }

    private var singleNumberInput: some View {
        TextField("0", value: $draftNumber, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(maxWidth: 90)
            .onAppear { syncDraftsFromRule() }
            .onChange(of: draftNumber) { _, n in scheduleCommit { .number(n) } }
    }

    private var rangeInput: some View {
        HStack(alignment: .center, spacing: 4) {
            TextField("from", value: $draftRangeLo, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 60)
                .onAppear { syncDraftsFromRule() }
                .onChange(of: draftRangeLo) { _, lo in scheduleCommit { .range(lo, self.draftRangeHi) } }
            Text("–").font(.caption).foregroundStyle(.secondary)
            TextField("to", value: $draftRangeHi, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 60)
                .onChange(of: draftRangeHi) { _, hi in scheduleCommit { .range(self.draftRangeLo, hi) } }
        }
    }

    // MARK: Days Input

    private var daysValueInput: some View {
        HStack(spacing: 4) {
            TextField("30", value: $draftNumber, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(maxWidth: 70)
                .onAppear { syncDraftsFromRule() }
                .onChange(of: draftNumber) { _, n in scheduleCommit { .number(n) } }
            Text("days").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Boolean Input

    private var booleanValueInput: some View {
        let binding = Binding<Bool>(
            get: { if case .boolean(let b) = rule.value { return b }; return true },
            set: { rule.value = .boolean($0) }
        )
        return Picker("", selection: binding) {
            Text("Yes").tag(true)
            Text("No").tag(false)
        }
        .pickerStyle(.segmented)
        .controlSize(.mini)
        .labelsHidden()
        .frame(maxWidth: 100)
    }

    // MARK: Debounce Helpers

    private func scheduleCommit(_ makeValue: @escaping @Sendable () -> FilterValue) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rule.value = makeValue()
        }
    }

    private func scheduleRegexValidation(_ pattern: String) {
        guard !pattern.isEmpty else { regexError = nil; return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rule.value = .text(pattern)
            let (rawPattern, options) = FilterRule.parseRegexLiteral(pattern)
            do {
                _ = try NSRegularExpression(pattern: rawPattern, options: options)
                regexError = nil
            } catch {
                regexError = "⚠ \(error.localizedDescription)"
            }
        }
    }

    private func syncDraftsFromRule() {
        switch rule.value {
        case .text(let s):       draftText = s
        case .number(let n):     draftNumber = n
        case .range(let lo, let hi): draftRangeLo = lo; draftRangeHi = hi
        case .boolean:           break
        }
        regexError = nil
    }
}

// MARK: - Save Smart Playlist Sheet

private struct SaveSmartPlaylistSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let ruleSet: FilterRuleSet

    @State private var name = ""
    @State private var comment = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSave = false

    private var activeRuleCount: Int { ruleSet.rules.filter { !$0.isEffectivelyEmpty }.count }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save as Smart Playlist")
                .font(.headline)

            if let ndClient = appState.navidromeClient {
                if ndClient.isAvailable {
                    formContent
                } else {
                    unavailableView
                }
            } else {
                unavailableView
            }

            Spacer(minLength: 0)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !didSave {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                } else {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 340, minHeight: 200)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Smart Playlist Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("", text: $comment)
                    .textFieldStyle(.roundedBorder)
            }
            Text("\(activeRuleCount) rule\(activeRuleCount == 1 ? "" : "s") will be saved")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Navidrome Smart Playlists are not available.")
                .font(.callout)
            Text("Connect to a Navidrome server to use this feature.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func save() {
        guard let ndClient = appState.navidromeClient, canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let criteria = NSPCriteria(from: ruleSet)
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await ndClient.createSmartPlaylist(name: trimmedName, comment: comment, rules: criteria)
                await MainActor.run {
                    isSaving = false
                    didSave = true
                }
                try? await Task.sleep(for: .seconds(1.2))
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
#endif
