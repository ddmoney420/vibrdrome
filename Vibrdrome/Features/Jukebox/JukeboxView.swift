import SwiftUI
import os.log

private let jukeboxLog = Logger(subsystem: "com.vibrdrome.app", category: "Jukebox")

struct JukeboxView: View {
    @Environment(AppState.self) private var appState
    @State private var playlist: JukeboxPlaylist?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var gain: Float = 0.5
    @State private var isDraggingGain = false
    @State private var pollTimer: Timer?

    var body: some View {
        Group {
            if let errorMessage {
                errorView(errorMessage)
            } else if isLoading, playlist == nil {
                ProgressView("Connecting to Jukebox...")
                    .accessibilityIdentifier("jukeboxLoading")
            } else {
                jukeboxContent
            }
        }
        .navigationTitle("Jukebox")
        .task {
            await refresh()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Content

    private var jukeboxContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                jukeboxBadge
                nowPlayingSection
                transportControls
                gainSlider
                toolbarActions
                queueSection
            }
            #if os(iOS)
            .padding(.bottom, 80)
            #endif
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Badge

    private var jukeboxBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "hifispeaker.fill")
                .font(.title3)
            Text("JUKEBOX MODE")
                .font(.headline)
                .fontWeight(.bold)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.15), in: Capsule())
        .padding(.top, 8)
        .accessibilityIdentifier("jukeboxBadge")
    }

    // MARK: - Now Playing

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let playlist, let entries = playlist.entry,
           let index = playlist.currentIndex, index >= 0, index < entries.count {
            let song = entries[index]
            VStack(spacing: 12) {
                AlbumArtView(coverArtId: song.coverArt, size: 200, cornerRadius: 12)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                Text(song.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(song.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let position = playlist.position {
                    positionLabel(position: position, duration: song.duration)
                }
            }
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No track playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)
        }
    }

    private func positionLabel(position: Int, duration: Int?) -> some View {
        HStack {
            Text(formatTime(position))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let duration {
                Spacer()
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button {
                Task { await skipPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("jukeboxPrevious")
            .accessibilityLabel("Previous")
            .disabled(currentIndex <= 0)

            Button {
                Task { await togglePlayStop() }
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 44))
            }
            .accessibilityIdentifier("jukeboxPlayStop")
            .accessibilityLabel(isPlaying ? "Stop" : "Play")

            Button {
                Task { await skipNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("jukeboxNext")
            .accessibilityLabel("Next")
            .disabled(!hasNextTrack)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Gain Slider

    private var gainSlider: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $gain, in: 0...1) { editing in
                    isDraggingGain = editing
                    if !editing {
                        Task { await setGain(gain) }
                    }
                }
                .accessibilityIdentifier("jukeboxGainSlider")
                .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Toolbar Actions

    private var toolbarActions: some View {
        HStack(spacing: 16) {
            Button {
                Task { await shuffleQueue() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("jukeboxShuffle")

            Button(role: .destructive) {
                Task { await clearQueue() }
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("jukeboxClear")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
    }

    // MARK: - Queue

    @ViewBuilder
    private var queueSection: some View {
        if let entries = playlist?.entry, !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Queue")
                    .font(.title3)
                    .bold()
                    .padding(.horizontal, 16)

                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, song in
                        queueRow(song: song, index: idx)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Text("Queue is empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Add songs from your library using the context menu.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
        }
    }

    private func queueRow(song: Song, index: Int) -> some View {
        Button {
            Task { await skipTo(index: index) }
        } label: {
            HStack(spacing: 12) {
                AlbumArtView(coverArtId: song.coverArt, size: 44, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(index == currentIndex ? .bold : .regular)
                        .foregroundStyle(index == currentIndex ? .orange : .primary)
                        .lineLimit(1)
                    Text(song.artist ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if index == currentIndex, isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let duration = song.duration {
                    Text(formatTime(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jukeboxQueueRow_\(index)")
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Jukebox Unavailable")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                errorMessage = nil
                Task { await refresh() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("jukeboxRetry")
        }
    }

    // MARK: - Helpers

    private var currentIndex: Int {
        playlist?.currentIndex ?? -1
    }

    private var isPlaying: Bool {
        playlist?.playing ?? false
    }

    private var hasNextTrack: Bool {
        guard let entries = playlist?.entry else { return false }
        return currentIndex < entries.count - 1
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await refresh(silent: true)
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Actions

    private func refresh(silent: Bool = false) async {
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }

        do {
            let result = try await appState.subsonicClient.jukeboxGet()
            playlist = result
            if !isDraggingGain {
                gain = result.gain ?? gain
            }
            errorMessage = nil
        } catch {
            if !silent {
                jukeboxLog.error("Jukebox refresh failed: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func togglePlayStop() async {
        do {
            if isPlaying {
                try await appState.subsonicClient.jukeboxStop()
            } else {
                try await appState.subsonicClient.jukeboxStart()
            }
            await refresh(silent: true)
        } catch {
            jukeboxLog.error("Jukebox play/stop failed: \(error)")
        }
    }

    private func skipTo(index: Int) async {
        do {
            try await appState.subsonicClient.jukeboxSkip(index: index)
            await refresh(silent: true)
        } catch {
            jukeboxLog.error("Jukebox skip failed: \(error)")
        }
    }

    private func skipPrevious() async {
        guard currentIndex > 0 else { return }
        await skipTo(index: currentIndex - 1)
    }

    private func skipNext() async {
        guard hasNextTrack else { return }
        await skipTo(index: currentIndex + 1)
    }

    private func setGain(_ value: Float) async {
        do {
            try await appState.subsonicClient.jukeboxSetGain(value)
        } catch {
            jukeboxLog.error("Jukebox setGain failed: \(error)")
        }
    }

    private func shuffleQueue() async {
        do {
            try await appState.subsonicClient.jukeboxShuffle()
            await refresh(silent: true)
        } catch {
            jukeboxLog.error("Jukebox shuffle failed: \(error)")
        }
    }

    private func clearQueue() async {
        do {
            try await appState.subsonicClient.jukeboxClear()
            await refresh(silent: true)
        } catch {
            jukeboxLog.error("Jukebox clear failed: \(error)")
        }
    }
}
