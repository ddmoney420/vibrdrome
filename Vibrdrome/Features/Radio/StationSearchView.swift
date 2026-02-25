import SwiftUI

// MARK: - Radio Browser API Model

private struct RadioBrowserStation: Decodable, Identifiable {
    let stationuuid: String
    let name: String
    let url_resolved: String?
    let url: String
    let homepage: String?
    let favicon: String?
    let tags: String?
    let country: String?
    let codec: String?
    let bitrate: Int?
    let votes: Int?

    var id: String { stationuuid }

    var streamUrl: String { url_resolved ?? url }

    var displayTags: [String] {
        guard let tags, !tags.isEmpty else { return [] }
        return tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0).capitalized }
    }
}

// MARK: - Station Search View

struct StationSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [RadioBrowserStation] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var addedIds = Set<String>()
    @State private var addingId: String?
    @State private var previewingId: String?
    @State private var error: String?
    @State private var browseTag = ""

    var onStationAdded: (() async -> Void)?

    private let popularTags = [
        "jazz", "rock", "electronic", "classical", "hip hop",
        "pop", "ambient", "lounge", "reggae", "blues",
        "metal", "country", "soul", "funk", "latin"
    ]

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Browse by genre tags
                    if results.isEmpty && query.isEmpty {
                        browseSection
                    }

                    // Results
                    if !results.isEmpty {
                        resultsSection
                    } else if isSearching {
                        ProgressView("Searching stations...")
                            .padding(.top, 60)
                    } else if !query.isEmpty && !isSearching {
                        ContentUnavailableView.search(text: query)
                            .padding(.top, 40)
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Find Stations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Search by name, genre, country...")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                browseTag = ""
                guard newValue.count >= 2 else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await searchStations(query: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Browse Section

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Genre")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 90), spacing: 8)
            ], spacing: 8) {
                ForEach(popularTags, id: \.self) { tag in
                    Button {
                        browseTag = tag
                        Task { await searchByTag(tag) }
                    } label: {
                        Text(tag.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                browseTag == tag
                                ? Color.accentColor.opacity(0.2)
                                : Color.secondary.opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundColor(browseTag == tag ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    // MARK: - Results

    private var resultsSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(results) { station in
                stationResultRow(station)
                if station.id != results.last?.id {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func stationResultRow(_ station: RadioBrowserStation) -> some View {
        HStack(spacing: 12) {
            stationIcon
            stationInfo(station)
            Spacer()
            stationPreviewButton(station)
            stationAddButton(station)
        }
        .padding(.vertical, 10)
    }

    private var stationIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: "radio")
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
        }
    }

    @ViewBuilder
    private func stationInfo(_ station: RadioBrowserStation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(station.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let country = station.country, !country.isEmpty {
                    Text(country)
                }
                if let codec = station.codec, !codec.isEmpty {
                    Text("·")
                    Text(codec.uppercased())
                }
                if let bitrate = station.bitrate, bitrate > 0 {
                    Text("·")
                    Text(verbatim: "\(bitrate)k")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if !station.displayTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(station.displayTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }

    private func stationPreviewButton(_ station: RadioBrowserStation) -> some View {
        Button {
            togglePreview(station)
        } label: {
            Image(systemName: previewingId == station.id ? "stop.circle.fill" : "play.circle")
                .font(.title3)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stationAddButton(_ station: RadioBrowserStation) -> some View {
        Button {
            Task { await addStation(station) }
        } label: {
            if addingId == station.id {
                ProgressView()
                    .frame(width: 28, height: 28)
            } else if addedIds.contains(station.id) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
            }
        }
        .buttonStyle(.plain)
        .disabled(addedIds.contains(station.id) || addingId == station.id)
    }

    // MARK: - Actions

    private func togglePreview(_ station: RadioBrowserStation) {
        if previewingId == station.id {
            engine.pause()
            previewingId = nil
        } else {
            let radioStation = InternetRadioStation.preview(
                id: station.id, name: station.name,
                streamUrl: station.streamUrl, homePageUrl: station.homepage
            )
            engine.playRadio(station: radioStation)
            previewingId = station.id
        }
    }

    private func addStation(_ station: RadioBrowserStation) async {
        addingId = station.id
        defer { addingId = nil }
        do {
            try await appState.subsonicClient.createRadioStation(
                streamUrl: station.streamUrl,
                name: station.name,
                homepageUrl: station.homepage
            )
            addedIds.insert(station.id)
            await onStationAdded?()
        } catch {
            self.error = "Failed to add: \(ErrorPresenter.userMessage(for: error))"
        }
    }

    // MARK: - API

    private func searchStations(query: String) async {
        isSearching = true
        error = nil
        defer { isSearching = false }

        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
            let urlString = "https://de1.api.radio-browser.info/json/stations/byname/\(encoded)?limit=30&order=votes&reverse=true"
            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.setValue("Vibrdrome/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let stations = try JSONDecoder().decode([RadioBrowserStation].self, from: data)
            guard !Task.isCancelled else { return }
            results = stations
        } catch {
            guard !Task.isCancelled else { return }
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func searchByTag(_ tag: String) async {
        isSearching = true
        error = nil
        results = []
        defer { isSearching = false }

        do {
            let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
            let urlString = "https://de1.api.radio-browser.info/json/stations/bytag/\(encoded)?limit=30&order=votes&reverse=true"
            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.setValue("Vibrdrome/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let stations = try JSONDecoder().decode([RadioBrowserStation].self, from: data)
            guard !Task.isCancelled else { return }
            results = stations
        } catch {
            guard !Task.isCancelled else { return }
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}

// MARK: - Preview helper

private extension InternetRadioStation {
    static func preview(id: String, name: String, streamUrl: String, homePageUrl: String?) -> InternetRadioStation {
        // We need to create an InternetRadioStation for preview playback
        // Since it's Decodable, we'll use JSON decoding
        var json: [String: Any] = ["id": id, "name": name, "streamUrl": streamUrl]
        if let homePageUrl { json["homePageUrl"] = homePageUrl }
        // swiftlint:disable:next force_try
        let data = try! JSONSerialization.data(withJSONObject: json)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(InternetRadioStation.self, from: data)
    }
}
