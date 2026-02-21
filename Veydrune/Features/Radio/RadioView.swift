import SwiftUI

struct RadioView: View {
    @Environment(AppState.self) private var appState
    @State private var stations: [InternetRadioStation] = []
    @State private var isLoading = true
    @State private var error: String?

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            List(stations) { station in
                Button {
                    engine.playRadio(station: station)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name)
                                .font(.body)
                                .lineLimit(1)
                            if let url = station.homePageUrl, !url.isEmpty {
                                Text(url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if isCurrentStation(station) {
                            Image(systemName: "waveform")
                                .foregroundColor(.accentColor)
                                .symbolEffect(.variableColor)
                        }
                    }
                }
                .tint(.primary)
            }
            .listStyle(.plain)
            .navigationTitle("Radio")
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
                } else if !isLoading && stations.isEmpty {
                    ContentUnavailableView {
                        Label("No Stations", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("No radio stations configured on the server")
                    }
                }
            }
            .task { await loadStations() }
            .refreshable { await loadStations() }
        }
    }

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
            self.error = error.localizedDescription
        }
    }
}
