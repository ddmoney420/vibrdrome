import SwiftUI
import os.log

// MARK: - GetInfoTarget

/// Identifies which item to show info for. Codable so it can be used with openWindow(id:value:).
struct GetInfoTarget: Codable, Hashable {
    enum ItemType: String, Codable { case song, album, artist }
    let type: ItemType
    let id: String
}

// MARK: - GetInfoViewModel

@Observable
@MainActor
final class GetInfoViewModel {
    // Song
    var song: Song?
    // Album
    var album: Album?
    var albumInfo: AlbumInfo2?
    // Artist
    var artist: Artist?
    var artistInfo: ArtistInfo2?
    // Raw API metadata payloads, including fields not modeled in typed structs
    var rawMetadataPayloads: [String: Any] = [:]
    // Common state
    var isLoading = false
    var errorMessage: String?

    func load(target: GetInfoTarget, client: SubsonicClient) async {
        isLoading = true
        errorMessage = nil
        rawMetadataPayloads = [:]
        defer { isLoading = false }
        do {
            switch target.type {
            case .song:
                async let songResult = client.getSong(id: target.id)
                let s = try await songResult
                song = s
                if let rawSong = try? await client.rawSubsonicResponse(for: .getSong(id: target.id)) {
                    rawMetadataPayloads["getSong"] = rawSong
                }
                if let inspect = try? await client.inspectMetadata(id: target.id) {
                    rawMetadataPayloads["inspect"] = inspect
                }
                // Also fetch album info if available
                if let albumId = s.albumId {
                    albumInfo = try? await client.getAlbumInfo(id: albumId)
                    if let rawAlbumInfo = try? await client.rawSubsonicResponse(for: .getAlbumInfo2(id: albumId)) {
                        rawMetadataPayloads["getAlbumInfo2"] = rawAlbumInfo
                    }
                }
            case .album:
                async let albumResult = client.getAlbum(id: target.id)
                async let infoResult = client.getAlbumInfo(id: target.id)
                album = try await albumResult
                albumInfo = try? await infoResult
                if let rawAlbum = try? await client.rawSubsonicResponse(for: .getAlbum(id: target.id)) {
                    rawMetadataPayloads["getAlbum"] = rawAlbum
                }
                if let rawAlbumInfo = try? await client.rawSubsonicResponse(for: .getAlbumInfo2(id: target.id)) {
                    rawMetadataPayloads["getAlbumInfo2"] = rawAlbumInfo
                }
            case .artist:
                async let artistResult = client.getArtist(id: target.id)
                async let infoResult = client.getArtistInfo(id: target.id)
                artist = try await artistResult
                artistInfo = try? await infoResult
                if let rawArtist = try? await client.rawSubsonicResponse(for: .getArtist(id: target.id)) {
                    rawMetadataPayloads["getArtist"] = rawArtist
                }
                if let rawArtistInfo = try? await client.rawSubsonicResponse(for: .getArtistInfo2(id: target.id)) {
                    rawMetadataPayloads["getArtistInfo2"] = rawArtistInfo
                }
            }
        } catch {
            errorMessage = ErrorPresenter.userMessage(for: error)
        }
    }
}

// MARK: - GetInfoView

struct GetInfoView: View {
    let target: GetInfoTarget

    @Environment(AppState.self) private var appState
    @State private var vm = GetInfoViewModel()

    var body: some View {
        Group {
            if vm.isLoading && !hasContent {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let err = vm.errorMessage, !hasContent {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Retry") { Task { await vm.load(target: target, client: appState.subsonicClient) } }
                        .buttonStyle(.bordered)
                }
            } else {
                TabView {
                    overviewTab
                        .tabItem { Text("Overview") }
                    rawMetadataTab
                        .tabItem { Text("Raw metadata") }
                }
            }
        }
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load(target: target, client: appState.subsonicClient) }
    }

    @ViewBuilder
    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch target.type {
                case .song:
                    if let song = vm.song {
                        songContent(song)
                    }
                case .album:
                    if let album = vm.album {
                        albumContent(album)
                    }
                case .artist:
                    if let artist = vm.artist {
                        artistContent(artist)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var rawMetadataTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if rawMetadataRows.isEmpty {
                    ContentUnavailableView {
                        Label("No Metadata", systemImage: "doc.text")
                    } description: {
                        Text("No raw metadata is available for this item.")
                    }
                } else {
                    Text("Raw metadata")
                        .font(.headline)

                    rawMetadataTable
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasContent: Bool {
        vm.song != nil || vm.album != nil || vm.artist != nil
    }

    private var navigationTitle: String {
        if let s = vm.song { return s.title }
        if let a = vm.album { return a.name }
        if let a = vm.artist { return a.name }
        return "Get Info"
    }

    // MARK: - Song Content

    // swiftlint:disable cyclomatic_complexity
    @ViewBuilder
    private func songContent(_ song: Song) -> some View {
        // Art + title header
        VStack(spacing: 16) {
            AlbumArtView(coverArtId: song.coverArt, size: 220, cornerRadius: 12)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)

            VStack(spacing: 4) {
                Text(song.title)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                if let artist = song.artist {
                    Text(artist).font(.body).foregroundStyle(.secondary)
                }
                if let album = song.album {
                    Text(album).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }

        sectionHeader("Track Details")
        infoGrid {
            if let track = song.track { infoCell("Track", "\(track)") }
            if let disc = song.discNumber { infoCell("Disc", "\(disc)") }
            if let year = song.year { infoCell("Year", "\(year)") }
            if let genre = song.genre { infoCell("Genre", genre) }
            if let duration = song.duration { infoCell("Duration", formatDuration(duration)) }
            if let bpm = song.bpm, bpm > 0 { infoCell("BPM", "\(bpm)") }
        }

        sectionHeader("Audio")
        infoGrid {
            if let suffix = song.suffix { infoCell("Format", suffix.uppercased()) }
            if let bitRate = song.bitRate { infoCell("Bitrate", "\(bitRate) kbps") }
            if let size = song.size { infoCell("File Size", formatBytes(size)) }
            if let contentType = song.contentType { infoCell("MIME Type", contentType) }
            if let rg = song.replayGain {
                if let tg = rg.trackGain { infoCell("Track Gain", String(format: "%.2f dB", tg)) }
                if let ag = rg.albumGain { infoCell("Album Gain", String(format: "%.2f dB", ag)) }
                if let tp = rg.trackPeak { infoCell("Track Peak", String(format: "%.4f", tp)) }
            }
        }

        sectionHeader("Identifiers")
        infoGrid {
            infoCell("Song ID", song.id)
            if let albumId = song.albumId { infoCell("Album ID", albumId) }
            if let artistId = song.artistId { infoCell("Artist ID", artistId) }
            if let parent = song.parent { infoCell("Parent ID", parent) }
            if let mbid = song.musicBrainzId { infoCell("MusicBrainz ID", mbid) }
            if let path = song.path { infoCell("Path", path) }
            if let created = song.created { infoCell("Added", created) }
        }

        if let notes = vm.albumInfo?.notes, !notes.isEmpty {
            sectionHeader("Album Notes")
            Text(stripHtml(notes))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }

        externalLinksSection(mbid: song.musicBrainzId, lastFmUrl: vm.albumInfo?.lastFmUrl)
    }
    // swiftlint:enable cyclomatic_complexity

    // MARK: - Album Content

    // swiftlint:disable cyclomatic_complexity function_body_length
    @ViewBuilder
    private func albumContent(_ album: Album) -> some View {
        VStack(spacing: 16) {
            AlbumArtView(coverArtId: album.coverArt, size: 220, cornerRadius: 12)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)

            VStack(spacing: 4) {
                Text(album.name)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                if let artist = album.artist {
                    Text(artist).font(.body).foregroundStyle(.secondary)
                }
            }
        }

        sectionHeader("Album Details")
        infoGrid {
            if let year = album.year { infoCell("Year", "\(year)") }
            if let genre = album.genre { infoCell("Genre", genre) }
            if let count = album.songCount { infoCell("Tracks", "\(count)") }
            if let dur = album.duration { infoCell("Duration", formatDuration(dur)) }
            if let created = album.created { infoCell("Added", created) }
        }

        sectionHeader("Identifiers")
        infoGrid {
            infoCell("Album ID", album.id)
            if let artistId = album.artistId { infoCell("Artist ID", artistId) }
            if let mbid = vm.albumInfo?.musicBrainzId { infoCell("MusicBrainz ID", mbid) }
        }

        if let rg = album.replayGain {
            sectionHeader("Replay Gain")
            infoGrid {
                if let ag = rg.albumGain { infoCell("Album Gain", String(format: "%.2f dB", ag)) }
                if let tg = rg.trackGain { infoCell("Track Gain", String(format: "%.2f dB", tg)) }
                if let ap = rg.albumPeak { infoCell("Album Peak", String(format: "%.4f", ap)) }
                if let tp = rg.trackPeak { infoCell("Track Peak", String(format: "%.4f", tp)) }
            }
        }

        if let notes = vm.albumInfo?.notes, !notes.isEmpty {
            sectionHeader("Notes")
            Text(stripHtml(notes))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }

        externalLinksSection(mbid: vm.albumInfo?.musicBrainzId, lastFmUrl: vm.albumInfo?.lastFmUrl)

        if let songs = album.song, !songs.isEmpty {
            sectionHeader("Tracks (\(songs.count))")
            VStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { idx, track in
                    HStack {
                        Text("\(track.track ?? idx + 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)
                        Text(track.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        if let dur = track.duration {
                            Text(formatDuration(dur))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    if idx < songs.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    // MARK: - Artist Content

    @ViewBuilder
    private func artistContent(_ artist: Artist) -> some View {
        VStack(spacing: 16) {
            AlbumArtView(coverArtId: artist.coverArt, size: 180, cornerRadius: 90)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)

            VStack(spacing: 4) {
                Text(artist.name)
                    .font(.title2).bold()
                if let count = artist.albumCount {
                    Text("\(count) album\(count == 1 ? "" : "s")")
                        .font(.body).foregroundStyle(.secondary)
                }
            }
        }

        sectionHeader("Identifiers")
        infoGrid {
            infoCell("Artist ID", artist.id)
            if let mbid = vm.artistInfo?.musicBrainzId { infoCell("MusicBrainz ID", mbid) }
        }

        if let bio = vm.artistInfo?.biography, !bio.isEmpty {
            sectionHeader("Biography")
            Text(stripHtml(bio))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }

        externalLinksSection(mbid: vm.artistInfo?.musicBrainzId, lastFmUrl: vm.artistInfo?.lastFmUrl)

        if let similar = vm.artistInfo?.similarArtist, !similar.isEmpty {
            sectionHeader("Similar Artists")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(similar) { a in
                    HStack {
                        AlbumArtView(coverArtId: a.coverArt, size: 36, cornerRadius: 18)
                        Text(a.name).font(.caption).lineLimit(1)
                        Spacer()
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }

        if let albums = artist.album, !albums.isEmpty {
            sectionHeader("Albums (\(albums.count))")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(albums) { alb in
                    VStack(spacing: 6) {
                        AlbumArtView(coverArtId: alb.coverArt, size: 100, cornerRadius: 8)
                        Text(alb.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let year = alb.year {
                            Text("\(year)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func infoGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10, content: content)
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func externalLinksSection(mbid: String?, lastFmUrl: String?) -> some View {
        let hasMbid = mbid != nil
        let hasLastFm = lastFmUrl != nil
        if hasMbid || hasLastFm {
            sectionHeader("External Links")
            HStack(spacing: 10) {
                if let mbid, let url = URL(string: "https://musicbrainz.org/recording/\(mbid)") {
                    Link(destination: url) {
                        Label("MusicBrainz", systemImage: "globe")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                if let lfm = lastFmUrl, let url = URL(string: lfm) {
                    Link(destination: url) {
                        Label("Last.fm", systemImage: "globe")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func stripHtml(_ html: String) -> String {
        // Simple regex-free strip: remove tags
        var result = html
        while let start = result.range(of: "<"), let end = result.range(of: ">", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound...end.lowerBound)
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Raw Metadata

    private struct RawMetadataRow: Identifiable {
        let key: String
        let value: String
        var id: String { "\(key)=\(value)" }
    }

    private var rawMetadataRows: [RawMetadataRow] {
        var rows: [RawMetadataRow] = []

        if !vm.rawMetadataPayloads.isEmpty {
            flattenMetadata(value: vm.rawMetadataPayloads, keyPath: "rawApi", rows: &rows)
        }

        switch target.type {
        case .song:
            if let song = vm.song {
                flattenMetadata(value: song, keyPath: "song", rows: &rows)
            }
            if let albumInfo = vm.albumInfo {
                flattenMetadata(value: albumInfo, keyPath: "albumInfo", rows: &rows)
            }
        case .album:
            if let album = vm.album {
                flattenMetadata(value: album, keyPath: "album", rows: &rows)
            }
            if let albumInfo = vm.albumInfo {
                flattenMetadata(value: albumInfo, keyPath: "albumInfo", rows: &rows)
            }
        case .artist:
            if let artist = vm.artist {
                flattenMetadata(value: artist, keyPath: "artist", rows: &rows)
            }
            if let artistInfo = vm.artistInfo {
                flattenMetadata(value: artistInfo, keyPath: "artistInfo", rows: &rows)
            }
        }

        return rows.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    @ViewBuilder
    private var rawMetadataTable: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text("Key")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 220, alignment: .leading)
                Text("Value")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ForEach(rawMetadataRows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Text(row.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 220, alignment: .leading)
                        .textSelection(.enabled)
                    Text(row.value)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if row.id != rawMetadataRows.last?.id {
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // swiftlint:disable cyclomatic_complexity
    private func flattenMetadata(value: Any, keyPath: String, rows: inout [RawMetadataRow]) {
        let mirror = Mirror(reflecting: value)

        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                flattenMetadata(value: child.value, keyPath: keyPath, rows: &rows)
            } else {
                rows.append(RawMetadataRow(key: keyPath, value: "nil"))
            }
            return
        }

        if mirror.children.isEmpty {
            rows.append(RawMetadataRow(key: keyPath, value: scalarDescription(value)))
            return
        }

        switch mirror.displayStyle {
        case .collection, .set:
            if mirror.children.isEmpty {
                rows.append(RawMetadataRow(key: keyPath, value: "[]"))
            } else {
                let values = Array(mirror.children.map(\.value))
                if let scalarValues = scalarCollectionValues(values) {
                    rows.append(RawMetadataRow(key: keyPath, value: scalarValues.joined(separator: ", ")))
                } else {
                    for (index, child) in mirror.children.enumerated() {
                        flattenMetadata(value: child.value, keyPath: "\(keyPath)[\(index)]", rows: &rows)
                    }
                }
            }
        case .dictionary:
            if mirror.children.isEmpty {
                rows.append(RawMetadataRow(key: keyPath, value: "[:]"))
            } else {
                for child in mirror.children {
                    let tuple = Mirror(reflecting: child.value)
                    let tupleChildren = Array(tuple.children)
                    if tupleChildren.count == 2 {
                        let key = scalarDescription(tupleChildren[0].value)
                        let childPath = appendDictionaryKey(base: keyPath, key: key)
                        flattenMetadata(value: tupleChildren[1].value, keyPath: childPath, rows: &rows)
                    }
                }
            }
        case .struct, .class, .tuple:
            for child in mirror.children {
                let childLabel = sanitizeLabel(child.label)
                let childPath = keyPath.isEmpty ? childLabel : "\(keyPath).\(childLabel)"
                flattenMetadata(value: child.value, keyPath: childPath, rows: &rows)
            }
        case .enum:
            rows.append(RawMetadataRow(key: keyPath, value: scalarDescription(value)))
        case .none:
            rows.append(RawMetadataRow(key: keyPath, value: scalarDescription(value)))
        @unknown default:
            rows.append(RawMetadataRow(key: keyPath, value: scalarDescription(value)))
        }
    }
    // swiftlint:enable cyclomatic_complexity

    private func scalarDescription(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let value = value as? String { return value }
        if let value = value as? Int { return String(value) }
        if let value = value as? Int64 { return String(value) }
        if let value = value as? Double { return String(value) }
        if let value = value as? Float { return String(value) }
        if let value = value as? Bool { return value ? "true" : "false" }
        if let value = value as? URL { return value.absoluteString }
        if let value = value as? Date {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: value)
        }
        return String(describing: value)
    }

    private func sanitizeLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return "value" }
        if label.hasPrefix(".") {
            return "item\(label)"
        }
        return label
    }

    private func appendDictionaryKey(base: String, key: String) -> String {
        let keyIsIdentifier = key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
        if keyIsIdentifier {
            return base.isEmpty ? key : "\(base).\(key)"
        }

        let escaped = key.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\(base)[\"\(escaped)\"]"
    }

    private func scalarCollectionValues(_ values: [Any]) -> [String]? {
        var rendered: [String] = []
        rendered.reserveCapacity(values.count)

        for value in values {
            guard let scalar = scalarValueIfSimple(value) else {
                return nil
            }
            rendered.append(scalar)
        }

        return rendered
    }

    private func scalarValueIfSimple(_ value: Any) -> String? {
        let mirror = Mirror(reflecting: value)

        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return scalarValueIfSimple(child.value)
            }
            return "nil"
        }

        if mirror.children.isEmpty {
            return scalarDescription(value)
        }

        switch mirror.displayStyle {
        case .dictionary:
            // Treat dictionaries with exactly one scalar value as simple.
            let entries = Array(mirror.children)
            guard entries.count == 1 else { return nil }
            let tuple = Mirror(reflecting: entries[0].value)
            let tupleChildren = Array(tuple.children)
            guard tupleChildren.count == 2 else { return nil }
            return scalarValueIfSimple(tupleChildren[1].value)

        case .struct, .class, .tuple:
            // Treat single-field objects as simple values (e.g. {"name": "Electronic"}).
            let children = Array(mirror.children)
            guard children.count == 1 else { return nil }
            return scalarValueIfSimple(children[0].value)

        default:
            return nil
        }
    }
}
