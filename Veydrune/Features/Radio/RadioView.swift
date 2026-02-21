import SwiftUI
import os.log

struct RadioView: View {
    @Environment(AppState.self) private var appState
    @State private var stations: [InternetRadioStation] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showSearchSheet = false

    private var engine: AudioEngine { AudioEngine.shared }

    private var filteredStations: [InternetRadioStation] {
        if searchText.isEmpty { return stations }
        return stations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // Rotating accent colors for station cards
    private static let stationColors: [Color] = [
        .red, .orange, .yellow, .green, .teal, .cyan, .blue, .indigo, .purple, .pink
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Action buttons (iOS inline, macOS uses toolbar)
                #if os(iOS)
                HStack(spacing: 12) {
                    Button { showSearchSheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.purple)
                            Text("Find Stations")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button { showAddSheet = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("Add URL")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                #endif

                // Now Playing station highlight
                if let current = engine.currentRadioStation,
                   stations.contains(where: { $0.id == current.id }) {
                    nowPlayingCard(current)
                        .padding(.horizontal, 16)
                }

                // Station grid
                if !filteredStations.isEmpty {
                    stationGrid
                } else if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                }
            }
            #if os(iOS)
            .padding(.bottom, 80)
            #endif
        }
        .navigationTitle("Radio")
        .searchable(text: $searchText, prompt: "Filter stations...")
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { showSearchSheet = true } label: {
                    Label("Find Stations", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem {
                Button { showAddSheet = true } label: {
                    Label("Add URL", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { Task { await loadStations() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .sheet(isPresented: $showAddSheet) {
            AddStationView {
                await loadStations()
            }
            .environment(appState)
        }
        .sheet(isPresented: $showSearchSheet) {
            StationSearchView {
                await loadStations()
            }
            .environment(appState)
        }
        .overlay {
            if isLoading && stations.isEmpty {
                ProgressView("Loading stations...")
            } else if let error, stations.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadStations() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && stations.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Stations", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Tap + to add a radio station")
                }
            }
        }
        .task { await loadStations() }
        .refreshable { await loadStations() }
    }

    // MARK: - Now Playing Card

    private func nowPlayingCard(_ station: InternetRadioStation) -> some View {
        Button {
            engine.playRadio(station: station)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.linearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PLAYING")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Text(station.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Now playing: \(station.name)")
    }

    // MARK: - Station Grid

    private var stationGrid: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredStations.enumerated()), id: \.element.id) { index, station in
                stationRow(station, colorIndex: index)

                if index < filteredStations.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func stationRow(_ station: InternetRadioStation, colorIndex: Int) -> some View {
        let color = Self.stationColors[colorIndex % Self.stationColors.count]
        let isPlaying = isCurrentStation(station)

        return Button {
            engine.playRadio(station: station)
        } label: {
            HStack(spacing: 14) {
                // Station icon with color
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.gradient.opacity(isPlaying ? 1.0 : 0.7))
                        .frame(width: 48, height: 48)
                    Image(systemName: "radio")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.body)
                        .fontWeight(isPlaying ? .semibold : .regular)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(station.streamUrl)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundColor(color)
                        .symbolEffect(.variableColor)
                        .accessibilityLabel("Playing")
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(color.opacity(0.6))
                        .accessibilityLabel("Play")
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteStation(station)
            } label: {
                Label("Delete Station", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func isCurrentStation(_ station: InternetRadioStation) -> Bool {
        engine.currentRadioStation?.id == station.id && engine.isPlaying
    }

    private func loadStations() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            stations = try await appState.subsonicClient.getRadioStations()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func deleteStation(_ station: InternetRadioStation) {
        stations.removeAll { $0.id == station.id }
        Task {
            do {
                try await appState.subsonicClient.deleteRadioStation(id: station.id)
            } catch {
                Logger(subsystem: "com.veydrune.app", category: "Radio")
                    .error("Failed to delete radio station: \(error)")
            }
        }
    }
}

// MARK: - Add Station Sheet

struct AddStationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var streamUrl = ""
    @State private var homepageUrl = ""
    @State private var isSaving = false
    @State private var error: String?

    var onSave: (() async -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Station Details") {
                    TextField("Station Name", text: $name, prompt: Text("My Radio Station"))
                    TextField("Stream URL", text: $streamUrl, prompt: Text("https://stream.example.com/live"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    TextField("Homepage (optional)", text: $homepageUrl, prompt: Text("https://example.com"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Text("Enter a direct stream URL (MP3, AAC, OGG). The station will be saved to your Navidrome server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Station")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || streamUrl.trimmingCharacters(in: .whitespaces).isEmpty
                                  || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                let homepage = homepageUrl.trimmingCharacters(in: .whitespaces)
                try await appState.subsonicClient.createRadioStation(
                    streamUrl: streamUrl.trimmingCharacters(in: .whitespaces),
                    name: name.trimmingCharacters(in: .whitespaces),
                    homepageUrl: homepage.isEmpty ? nil : homepage
                )
                await onSave?()
                dismiss()
            } catch {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }
}
