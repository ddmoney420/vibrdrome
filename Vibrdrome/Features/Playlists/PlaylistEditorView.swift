import SwiftUI

struct PlaylistEditorView: View {
    enum Mode {
        case create
        case edit(playlistId: String, currentName: String)
        /// Edit an existing Navidrome smart playlist — pre-loads its rules.
        case smartPlaylist(playlistId: String, currentName: String, existingRules: NSPCriteria?)
    }

    let mode: Mode
    var onSave: (() async -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var searchQuery = ""
    @State private var searchResults: [Song] = []
    @State private var selectedSongs: [Song] = []
    @State private var isSaving = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    // Smart playlist state
    @State private var ruleSet: FilterRuleSet = .init()
    @State private var sortEntries: [SortEntry] = []
    @State private var limitEnabled: Bool = false
    @State private var limit: Int = 25

    init(mode: Mode, onSave: (() async -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            self._name = State(initialValue: "")
        case .edit(_, let currentName):
            self._name = State(initialValue: currentName)
        case .smartPlaylist(_, let currentName, let existing):
            self._name = State(initialValue: currentName)
            if let existing {
                self._ruleSet = State(initialValue: FilterRuleSet(from: existing))
                // Parse comma-separated sort string into SortEntry list.
                // Each component is optionally prefixed with "-" (desc) or "+" (asc).
                // A bare global `order: "desc"` with no per-field prefix flips all entries.
                let globalDesc = (existing.order == "desc")
                let entries: [SortEntry] = (existing.sort ?? "")
                    .split(separator: ",")
                    .compactMap { token -> SortEntry? in
                        let s = token.trimmingCharacters(in: .whitespaces)
                        guard !s.isEmpty else { return nil }
                        if s.hasPrefix("-") {
                            return SortEntry(field: String(s.dropFirst()), descending: true)
                        } else if s.hasPrefix("+") {
                            return SortEntry(field: String(s.dropFirst()), descending: false)
                        } else {
                            return SortEntry(field: s, descending: globalDesc)
                        }
                    }
                self._sortEntries = State(initialValue: entries)
                if let l = existing.limit, l > 0 {
                    self._limitEnabled = State(initialValue: true)
                    self._limit = State(initialValue: l)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("Name", text: $name, prompt: Text("My Playlist"))
                }

                if isCreating {
                    addSongsSection
                }

                if isSmart {
                    smartRulesSection
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 580, minHeight: isSmart ? 420 : 160)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("playlistEditorCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSmart ? "Update" : (isCreating ? "Create" : "Save")) {
                        save()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .accessibilityIdentifier("playlistEditorSaveButton")
                }
            }
        }
    }

    // MARK: - Regular playlist song search

    private var addSongsSection: some View {
        Group {
            Section("Add Songs") {
                TextField("Search songs...", text: $searchQuery)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: searchQuery) { _, newValue in
                        searchTask?.cancel()
                        guard newValue.count >= 2 else { searchResults = []; return }
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            let results = try? await appState.subsonicClient.search(
                                query: newValue, artistCount: 0, albumCount: 0, songCount: 30)
                            searchResults = results?.song ?? []
                        }
                    }

                ForEach(searchResults) { song in
                    Button {
                        if !selectedSongs.contains(where: { $0.id == song.id }) {
                            selectedSongs.append(song)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.body).lineLimit(1)
                                Text(song.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: selectedSongs.contains(where: { $0.id == song.id })
                                  ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(selectedSongs.contains(where: { $0.id == song.id }) ? Color.green : .secondary)
                        }
                    }
                    .tint(.primary)
                }
            }

            if !selectedSongs.isEmpty {
                Section("Selected (\(selectedSongs.count))") {
                    ForEach(selectedSongs) { song in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.body).lineLimit(1)
                            Text(song.artist ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in selectedSongs.remove(atOffsets: offsets) }
                    .onMove { source, destination in selectedSongs.move(fromOffsets: source, toOffset: destination) }
                }
            }
        }
    }

    // MARK: - Smart playlist rule builder

    private var smartRulesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Match")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $ruleSet.combinator) {
                        Text("ALL rules").tag(FilterRuleSet.Combinator.all)
                        Text("ANY rule").tag(FilterRuleSet.Combinator.any)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                if !ruleSet.rules.isEmpty {
                    Divider()
                }

                ForEach($ruleSet.rules) { $rule in
                    InlineRuleRowView(rule: $rule, allowedFields: FilterField.smartPlaylistFields) {
                        ruleSet.rules.removeAll { $0.id == rule.id }
                    }
                    Divider()
                }

                Button {
                    let field = FilterField.smartPlaylistFields.first ?? .title
                    let op = FilterOperator.allowed(for: field.kind).first ?? .contains
                    ruleSet.rules.append(FilterRule(field: field, operator: op,
                                                    value: .defaultValue(for: field.kind)))
                } label: {
                    Label("Add Rule", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                let activeCount = ruleSet.rules.filter { !$0.isEffectivelyEmpty }.count
                if activeCount > 0 {
                    Text("\(activeCount) active rule\(activeCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Sort — supports multiple fields, each with independent direction
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sort by")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            sortEntries.append(SortEntry(field: NSPSortField.title.rawValue, descending: false))
                        } label: {
                            Label("Add Sort Field", systemImage: "plus.circle")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .disabled(sortEntries.count >= NSPSortField.allCases.count)
                    }

                    ForEach($sortEntries) { $entry in
                        HStack(spacing: 6) {
                            Picker("", selection: $entry.field) {
                                ForEach(NSPSortField.allCases, id: \.rawValue) {
                                    Text($0.displayName).tag($0.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 140)

                            Picker("", selection: $entry.descending) {
                                Text("Ascending").tag(false)
                                Text("Descending").tag(true)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 130)
                            .disabled(entry.field == NSPSortField.random.rawValue)

                            Button {
                                sortEntries.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                    }

                    if sortEntries.isEmpty {
                        Text("None")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Limit
                HStack(spacing: 8) {
                    Toggle(isOn: $limitEnabled) {
                        Text("Limit to")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif

                    if limitEnabled {
                        TextField("", value: $limit, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("songs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .padding(.vertical, 6)
        } header: {
            Label("Smart Rules", systemImage: "sparkles")
        } footer: {
            Text("Rules run on the server. Changes take effect on next playlist refresh.")
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var isSmart: Bool {
        if case .smartPlaylist = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .create:           return "New Playlist"
        case .edit:             return "Edit Playlist"
        case .smartPlaylist:    return "Edit Smart Playlist"
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                switch mode {
                case .create:
                    let songIds = selectedSongs.map(\.id)
                    try await appState.subsonicClient.createPlaylist(
                        name: name.trimmingCharacters(in: .whitespaces),
                        songIds: songIds
                    )
                case .edit(let playlistId, _):
                    try await appState.subsonicClient.updatePlaylist(
                        id: playlistId,
                        name: name.trimmingCharacters(in: .whitespaces)
                    )
                case .smartPlaylist(let playlistId, _, _):
                    guard let ndClient = appState.navidromeClient else {
                        errorMessage = "Navidrome native API not available"
                        return
                    }
                    // Navidrome supports comma-separated sort with per-field direction prefix.
                    // "-field" = descending, "field" = ascending (no prefix).
                    let sortValue: String? = sortEntries.isEmpty ? nil
                        : sortEntries.map { $0.descending ? "-\($0.field)" : $0.field }.joined(separator: ",")
                    let criteria = NSPCriteria(
                        from: ruleSet,
                        sort: sortValue,
                        order: nil,
                        limit: limitEnabled ? limit : nil
                    )
                    try await ndClient.updateSmartPlaylist(
                        id: playlistId,
                        name: name.trimmingCharacters(in: .whitespaces),
                        rules: criteria
                    )
                }
                await onSave?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - NSPCriteria → FilterRuleSet (reverse mapping for pre-population)

extension FilterRuleSet {
    /// Reconstruct a `FilterRuleSet` from an `NSPCriteria` so existing smart playlist
    /// rules can be displayed in the UI for editing.
    init(from criteria: NSPCriteria) {
        self.combinator = criteria.combinator == .all ? .all : .any
        self.rules = criteria.expressions.compactMap { FilterRule(from: $0) }
    }
}

private extension FilterRule {
    /// Reconstruct a `FilterRule` from an `NSPExpression` leaf.
    /// Returns nil for conjunctions (nested groups) — we don't support nested editing yet.
    init?(from expression: NSPExpression) {
        guard case .leaf(let op, let field, let value) = expression else { return nil }

        // inPlaylist / notInPlaylist: the "field" key is "id", not a regular field name.
        // Detect by the operator name and treat the value as the playlist ID.
        let opLower = op.lowercased()
        if opLower == "inplaylist" || opLower == "notinplaylist" {
            guard case .string(let playlistId) = value else { return nil }
            let filterField: FilterField = opLower == "inplaylist" ? .inPlaylist : .notInPlaylist
            self.init(field: filterField, operator: .isInPlaylist, value: .text(playlistId))
            return
        }

        guard let filterField = FilterField(nspField: field) else { return nil }
        guard let (filterOp, filterValue) = FilterRule.fromNSP(op: opLower, value: value, field: filterField) else { return nil }
        self.init(field: filterField, operator: filterOp, value: filterValue)
    }

    static func fromNSP(op: String, value: NSPValue, field: FilterField) -> (FilterOperator, FilterValue)? {
        switch field.kind {
        case .text:     return textFromNSP(op: op, value: value)
        case .numeric:  return numericFromNSP(op: op, value: value)
        case .days:     return daysFromNSP(op: op, value: value)
        case .boolean:  return booleanFromNSP(value: value)
        case .playlist: return nil  // handled in init?(from:) above
        }
    }

    private static func textFromNSP(op: String, value: NSPValue) -> (FilterOperator, FilterValue)? {
        guard case .string(let s) = value else { return nil }
        switch op {
        case "contains":    return (.contains, .text(s))
        case "notcontains": return (.notContains, .text(s))
        case "is":          return (.equals, .text(s))
        case "isnot":       return (.notEquals, .text(s))
        case "startswith":  return (.startsWith, .text(s))
        case "endswith":    return (.endsWith, .text(s))
        default:            return nil
        }
    }

    private static func numericFromNSP(op: String, value: NSPValue) -> (FilterOperator, FilterValue)? {
        func intFrom(_ v: NSPValue) -> Int? {
            switch v {
            case .int(let n):    return n
            case .double(let d): return Int(d)
            default:             return nil
            }
        }
        switch op {
        case "is":
            if let n = intFrom(value) { return (.isEqualTo, .number(n)) }
        case "isnot":
            if let n = intFrom(value) { return (.isNotEqualTo, .number(n)) }
        case "gt":
            if let n = intFrom(value) { return (.isGreaterThan, .number(n)) }
        case "lt":
            if let n = intFrom(value) { return (.isLessThan, .number(n)) }
        case "intherange":
            if case .range(let lo, let hi) = value,
               let loN = intFrom(lo), let hiN = intFrom(hi) {
                return (.isBetween, .range(loN, hiN))
            }
        default: break
        }
        return nil
    }

    private static func daysFromNSP(op: String, value: NSPValue) -> (FilterOperator, FilterValue)? {
        func intFrom(_ v: NSPValue) -> Int? {
            switch v {
            case .int(let n):    return n
            case .double(let d): return Int(d)
            default:             return nil
            }
        }
        switch op {
        case "inthelast":
            if let n = intFrom(value) { return (.inTheLast, .number(n)) }
        case "notinthelast":
            if let n = intFrom(value) { return (.notInTheLast, .number(n)) }
        case "before":
            if case .string(let date) = value { return (.before, .text(date)) }
        case "after":
            if case .string(let date) = value { return (.after, .text(date)) }
        default: break
        }
        return nil
    }

    private static func booleanFromNSP(value: NSPValue) -> (FilterOperator, FilterValue)? {
        guard case .bool(let b) = value else { return nil }
        return (.isTrue, .boolean(b))
    }
}

private extension FilterField {
    /// Reverse lookup: NSP field name → FilterField.
    init?(nspField: String) {
        let table: [String: FilterField] = [
            // Text
            "title": .title, "artist": .artist, "album": .albumTitle,
            "genre": .genre, "recordlabel": .label, "filetype": .suffix,
            "codec": .contentType, "comment": .comment,
            "explicitstatus": .explicitStatus,
            "mbz_recording_id": .mbzRecordingId, "mbz_album_id": .mbzAlbumId,
            "mbz_artist_id": .mbzArtistId, "mbz_album_artist_id": .mbzAlbumArtistId,
            "mbz_release_track_id": .mbzReleaseTrackId, "mbz_release_group_id": .mbzReleaseGroupId,
            // Numeric
            "year": .year, "duration": .duration, "size": .size, "channels": .channels,
            "bitrate": .bitRate, "bitdepth": .bitDepth, "samplerate": .sampleRate,
            "bpm": .bpm, "playcount": .playCount, "rating": .rating,
            "averagerating": .averageRating,
            "albumrating": .albumRating, "albumplaycount": .albumPlayCount,
            "artistrating": .artistRating, "artistplaycount": .artistPlayCount,
            "tracknumber": .trackNumber, "discnumber": .discNumber,
            // Date-relative
            "lastplayed": .lastPlayed, "dateloved": .dateLoved, "daterated": .dateRated,
            "dateadded": .dateAdded, "datemodified": .dateModified,
            "albumlastplayed": .albumLastPlayed, "albumdateloved": .albumDateLoved,
            "albumdaterated": .albumDateRated,
            "artistlastplayed": .artistLastPlayed, "artistdateloved": .artistDateLoved,
            "artistdaterated": .artistDateRated,
            // Boolean
            "loved": .isFavorited, "albumloved": .albumFavorited, "artistloved": .artistFavorited,
            "hascoverart": .hasCoverArt, "compilation": .isCompilation, "missing": .isMissing,
        ]
        guard let match = table[nspField] else { return nil }
        self = match
    }
}

// MARK: - Sort entry

private struct SortEntry: Identifiable {
    let id = UUID()
    var field: String
    var descending: Bool
}

// MARK: - Sort fields

private enum NSPSortField: String, CaseIterable {
    case title, artist, album, genre, year, duration
    case size
    case channels
    case bitRate = "bitrate"
    case bitDepth = "bitdepth"
    case sampleRate = "samplerate"
    case bpm
    case playCount = "playcount"
    case rating
    case averageRating = "averagerating"
    case albumRating = "albumrating"
    case albumPlayCount = "albumplaycount"
    case artistRating = "artistrating"
    case artistPlayCount = "artistplaycount"
    case trackNumber = "tracknumber"
    case discNumber = "discnumber"
    case lastPlayed = "lastplayed"
    case dateLoved = "dateloved"
    case dateRated = "daterated"
    case dateAdded = "dateadded"
    case dateModified = "datemodified"
    case albumLastPlayed = "albumlastplayed"
    case artistLastPlayed = "artistlastplayed"
    case random

    var displayName: String {
        switch self {
        case .title:           "Title"
        case .artist:          "Artist"
        case .album:           "Album"
        case .genre:           "Genre"
        case .year:            "Year"
        case .duration:        "Duration"
        case .size:            "File Size"
        case .channels:        "Channels"
        case .bitRate:         "Bit Rate"
        case .bitDepth:        "Bit Depth"
        case .sampleRate:      "Sample Rate"
        case .bpm:             "BPM"
        case .playCount:       "Play Count"
        case .rating:          "Rating"
        case .averageRating:   "Avg Rating"
        case .albumRating:     "Album Rating"
        case .albumPlayCount:  "Album Play Count"
        case .artistRating:    "Artist Rating"
        case .artistPlayCount: "Artist Play Count"
        case .trackNumber:     "Track #"
        case .discNumber:      "Disc #"
        case .lastPlayed:      "Last Played"
        case .dateLoved:       "Date Loved"
        case .dateRated:       "Date Rated"
        case .dateAdded:       "Date Added"
        case .dateModified:    "Date Modified"
        case .albumLastPlayed: "Album Last Played"
        case .artistLastPlayed: "Artist Last Played"
        case .random:          "Random"
        }
    }
}

// MARK: - Inline rule row (iOS/macOS shared, no NSColor dependency)

private struct InlineRuleRowView: View {
    @Binding var rule: FilterRule
    let allowedFields: [FilterField]
    let onRemove: () -> Void

    @State private var draftText: String = ""
    @State private var draftNumber: Int = 0
    @State private var draftRangeLo: Int = 0
    @State private var draftRangeHi: Int = 0
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $rule.field) {
                ForEach(allowedFields, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
            .onChange(of: rule.field) { _, newField in
                let ops = FilterOperator.allowed(for: newField.kind)
                if !ops.contains(rule.operator) { rule.operator = ops[0] }
                rule.value = .defaultValue(for: newField.kind)
                syncDrafts()
            }

            Picker("", selection: $rule.operator) {
                ForEach(FilterOperator.allowed(for: rule.field.kind), id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
            .onChange(of: rule.operator) { _, newOp in
                if newOp == .isBetween, case .number(let n) = rule.value {
                    rule.value = .range(n, n); draftRangeLo = n; draftRangeHi = n
                } else if newOp != .isBetween, case .range(let lo, _) = rule.value {
                    rule.value = .number(lo); draftNumber = lo
                } else if newOp == .before || newOp == .after, case .number = rule.value {
                    rule.value = .text(""); draftText = ""
                } else if newOp == .inTheLast || newOp == .notInTheLast, case .text = rule.value {
                    rule.value = .number(30); draftNumber = 30
                }
            }

            valueInput

            Button(action: onRemove) {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .onAppear { syncDrafts() }
    }

    @ViewBuilder
    private var valueInput: some View {
        switch rule.field.kind {
        case .text:
            TextField("value…", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onChange(of: draftText) { _, v in commit { .text(v) } }
        case .numeric:
            if rule.operator == .isBetween {
                HStack(spacing: 4) {
                    TextField("", value: $draftRangeLo, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: draftRangeLo) { _, lo in commit { .range(lo, self.draftRangeHi) } }
                    Text("–").foregroundStyle(.secondary)
                    TextField("", value: $draftRangeHi, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: draftRangeHi) { _, hi in commit { .range(self.draftRangeLo, hi) } }
                }
                .frame(maxWidth: .infinity)
            } else {
                TextField("", value: $draftNumber, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: draftNumber) { _, n in commit { .number(n) } }
            }
        case .days:
            if rule.operator == .before || rule.operator == .after {
                // Absolute date input: "YYYY-MM-DD"
                TextField("YYYY-MM-DD", text: $draftText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onChange(of: draftText) { _, v in commit { .text(v) } }
            } else {
                HStack(spacing: 6) {
                    TextField("", value: $draftNumber, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: draftNumber) { _, n in commit { .number(n) } }
                    Text("days").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        case .boolean:
            Picker("", selection: Binding(
                get: { if case .boolean(let b) = rule.value { return b }; return true },
                set: { rule.value = .boolean($0) }
            )) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        case .playlist:
            TextField("Playlist ID…", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onChange(of: draftText) { _, v in commit { .text(v) } }
        }
    }

    private func commit(_ make: @escaping @Sendable () -> FilterValue) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rule.value = make()
        }
    }

    private func syncDrafts() {
        switch rule.value {
        case .text(let s):          draftText = s
        case .number(let n):        draftNumber = n
        case .range(let lo, let hi): draftRangeLo = lo; draftRangeHi = hi
        case .boolean:              break
        }
    }
}
