import AVFoundation
import Foundation
import SwiftData

/// Why persistent construction failed.
///
/// Deliberately a closed set of coarse causes: a failure reason ends up in diagnostics and logs, so
/// it must never carry a credential, URL, file path or token.
enum PersistentPreparationFailure: String, Error, Equatable, Sendable, CaseIterable {
    /// No writable cache directory for prepared sources.
    case cacheDirectoryUnavailable
    /// The audio graph could not be assembled.
    case audioGraphUnavailable
    /// The builder declined to produce an assembly.
    case builderRefused
}

/// Where persistent construction has got to. Cold launch is always `.notConstructed`.
enum PersistentPreparationState: Equatable, Sendable {
    case notConstructed
    case constructing
    case ready
    case failed(PersistentPreparationFailure)
}

/// The production persistent playback stack — **assembled, not started**.
///
/// Construction attaches and connects the fixed 44.1 kHz stereo Float32 graph (that is
/// `PersistentGaplessEngine.init`'s job) and builds the controller, session and preparer. It does
/// **not** prepare the graph, start the engine, activate the audio session, open a source file,
/// create a converter, or allocate the buffer pool — the scheduler that owns the pool is a `lazy
/// var` on the backend, documented there as "built lazily so a backend that is never started
/// allocates no pool", and nothing here touches it.
///
/// Holding this object is therefore inert. `GaplessPlaybackController.play()` is the only path that
/// activates the session, and Lane 3C never calls it.
@MainActor
final class PersistentPlaybackAssembly {
    let session: GaplessPlaybackSession
    let backend: GaplessRealTimeBackend
    let preparer: GaplessTrackPreparer
    /// Not exposed to application callers — the router holds the assembly, and application code
    /// talks to `ApplicationPlaybackControlling`, never to a gapless type.
    let controller: GaplessPlaybackController
    let cacheDirectory: URL

    /// Increments per constructed assembly, so a test can prove only one was ever built.
    private(set) static var constructionCount = 0
    let generation: Int

    init(
        session: GaplessPlaybackSession,
        backend: GaplessRealTimeBackend,
        preparer: GaplessTrackPreparer,
        cacheDirectory: URL
    ) {
        self.session = session
        self.backend = backend
        self.preparer = preparer
        self.cacheDirectory = cacheDirectory
        self.controller = GaplessPlaybackController(
            session: session, backend: backend, preparer: preparer
        )
        Self.constructionCount += 1
        self.generation = Self.constructionCount
    }

    #if DEBUG
    static func resetConstructionCountForTesting() { constructionCount = 0 }
    #endif

    /// Inert-state readout for the Debug screen.
    ///
    /// **Deliberately does not read `backend.openFileCount`.** That property reaches through the
    /// backend's `lazy` buffer scheduler, so asking for it would allocate the very pool this lane
    /// is proving does not exist yet. Live source-file and converter counts are reported as absent
    /// on the same grounds: nothing has been scheduled, because nothing has played.
    struct Diagnostics: Equatable, Sendable {
        var generation: Int
        var graphFormat: String
        var engineRunning: Bool
        var playerNodePlaying: Bool
        var bufferPoolAllocated: Bool
        var bufferPoolCapacity: Int?
        var bufferPoolAvailable: Int?
        var liveSourceFiles: Int
        var liveConverters: Int
        var scheduledBuffers: Int
        var engineState: String

        var summary: String {
            """
            Persistent assembly: #\(generation)
            Graph format: \(graphFormat)
            Engine running: \(engineRunning ? "Yes" : "No")
            Player node playing: \(playerNodePlaying ? "Yes" : "No")
            Buffer pool: \(bufferPoolAllocated
                ? "\(bufferPoolAvailable ?? 0)/\(bufferPoolCapacity ?? 0) available"
                : "Not allocated (lazy)")
            Live source files: \(liveSourceFiles)
            Live converters: \(liveConverters)
            Scheduled buffers: \(scheduledBuffers)
            Engine state: \(engineState)
            """
        }
    }

    /// Reads only what can be read without allocating.
    var diagnostics: Diagnostics {
        let format = backend.engine.renderFormat
        return Diagnostics(
            generation: generation,
            graphFormat: "\(Int(format.sampleRate)) Hz / \(format.channelCount) ch / Float32",
            engineRunning: backend.engine.engine.isRunning,
            playerNodePlaying: backend.engine.player.isPlaying,
            // Nothing has played, so the lazy scheduler — and its pool — has never been built.
            bufferPoolAllocated: false,
            bufferPoolCapacity: nil,
            bufferPoolAvailable: nil,
            liveSourceFiles: 0,
            liveConverters: 0,
            scheduledBuffers: 0,
            engineState: "\(backend.state)"
        )
    }
}

// MARK: - Builder

/// Builds the persistent stack. A protocol so a test can make construction fail without a
/// device-only substitute or a change to the production architecture.
@MainActor
protocol PersistentPlaybackAssemblyBuilding {
    func build() throws -> PersistentPlaybackAssembly
}

/// The production builder. Uses the real persistent types — no test doubles.
@MainActor
struct ProductionPersistentPlaybackAssemblyBuilder: PersistentPlaybackAssemblyBuilding {

    /// Gapless-owned cache, separate from the user's downloads so reaping it can never delete music
    /// the user chose to keep offline.
    static let cacheDirectoryName = "GaplessPrepared"

    func build() throws -> PersistentPlaybackAssembly {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else {
            throw PersistentPreparationFailure.cacheDirectoryUnavailable
        }
        let cacheDirectory = caches.appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory, withIntermediateDirectories: true
            )
        } catch {
            throw PersistentPreparationFailure.cacheDirectoryUnavailable
        }

        let provider = GaplessStreamingFileProvider(
            cacheDirectory: cacheDirectory,
            existingLocalFile: { trackID in await Self.downloadedFile(forSongID: trackID) },
            remoteURL: { trackID in await Self.streamURL(forSongID: trackID) }
        )

        let backend = GaplessRealTimeBackend()
        // Wired, never invoked here. `GaplessPlaybackController.play()` is the only path that
        // activates the session, and Lane 3C never calls it.
        #if os(iOS)
        backend.activateAudioSession = {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try audio.setActive(true)
        }
        backend.deactivateAudioSession = {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        #endif

        return PersistentPlaybackAssembly(
            session: GaplessPlaybackSession(sampleRate: GaplessRenderFormat.sampleRate),
            backend: backend,
            preparer: GaplessTrackPreparer(
                provider: provider, renderSampleRate: GaplessRenderFormat.sampleRate
            ),
            cacheDirectory: cacheDirectory
        )
    }

    /// Same resolution the legacy engine uses: a complete `DownloadedSong` whose file still exists.
    private static func downloadedFile(forSongID songID: String) async -> URL? {
        await MainActor.run {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songID && $0.isComplete == true }
            )
            guard let download = try? context.fetch(descriptor).first else { return nil }
            let url = DownloadManager.absoluteURL(for: download.localFilePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// Resolved at fetch time so credentials and bitrate settings are current, rather than captured
    /// when the queue was built. Uses `AppState`'s client so this stays cross-platform —
    /// `SubsonicClientProvider` exists only on iOS.
    private static func streamURL(forSongID songID: String) async -> URL? {
        await MainActor.run {
            AppState.shared.subsonicClient.streamURL(id: songID)
        }
    }
}
