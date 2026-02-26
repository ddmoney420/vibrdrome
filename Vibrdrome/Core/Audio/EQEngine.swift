import AVFoundation
import Foundation
import Observation
import os.log

private let eqLog = Logger(subsystem: "com.vibrdrome.app", category: "EQ")

/// AVAudioEngine-based playback path with 10-band parametric EQ.
/// Works with any local file URL. For streamed tracks, AudioEngine downloads
/// to a temp file first, then hands off to this engine.
@Observable
@MainActor
final class EQEngine {
    static let shared = EQEngine()

    var isActive = false
    var currentPresetId: String = "flat"
    var customGains: [Float] = Array(repeating: 0, count: 10)

    /// Current playback position in seconds
    var currentTime: TimeInterval = 0

    /// Total duration of the current file in seconds
    var fileDuration: TimeInterval = 0

    /// Called when the current file finishes playing
    var onTrackEnd: (() -> Void)?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var eqNode: AVAudioUnitEQ?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var audioFile: AVAudioFile?
    private var fileSampleRate: Double = 44100
    private var totalFrames: AVAudioFramePosition = 0
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var timeUpdateTimer: Timer?

    private init() {}

    /// Start EQ playback for a local file URL
    func play(url: URL, rate: Float = 1.0, startTime: TimeInterval = 0) throws {
        stop()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 10)
        let timePitch = AVAudioUnitTimePitch()

        configureEQBands(eq)
        timePitch.rate = rate

        engine.attach(player)
        engine.attach(eq)
        engine.attach(timePitch)

        let file = try openAndConfigureFile(url: url)
        let fileFormat = file.processingFormat
        engine.connect(player, to: eq, format: fileFormat)
        engine.connect(eq, to: timePitch, format: fileFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: fileFormat)

        do {
            try engine.start()
        } catch {
            eqLog.error("Failed to start AVAudioEngine: \(error)")
            throw error
        }

        schedulePlayback(player: player, file: file, startTime: startTime)
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.eqNode = eq
        self.timePitchNode = timePitch
        self.audioFile = file
        isActive = true
        currentTime = startTime
        startTimeUpdates()
    }

    private func configureEQBands(_ eq: AVAudioUnitEQ) {
        for (i, freq) in EQPresets.frequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = customGains[i]
            band.bypass = false
        }
    }

    private func openAndConfigureFile(url: URL) throws -> AVAudioFile {
        let file = try AVAudioFile(forReading: url)
        fileSampleRate = file.processingFormat.sampleRate
        totalFrames = file.length
        fileDuration = Double(totalFrames) / fileSampleRate
        return file
    }

    private func schedulePlayback(
        player: AVAudioPlayerNode, file: AVAudioFile, startTime: TimeInterval
    ) {
        let startFrame = AVAudioFramePosition(startTime * fileSampleRate)
        let clampedStart = max(0, min(startFrame, totalFrames))
        seekFrameOffset = clampedStart

        if clampedStart > 0 && clampedStart < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - clampedStart)
            file.framePosition = clampedStart
            player.scheduleSegment(
                file, startingFrame: clampedStart, frameCount: remaining,
                at: nil
            ) { [weak self] in
                Task { @MainActor in self?.handlePlaybackComplete() }
            }
        } else {
            player.scheduleFile(file, at: nil) { [weak self] in
                Task { @MainActor in self?.handlePlaybackComplete() }
            }
        }
    }

    func pause() {
        playerNode?.pause()
        stopTimeUpdates()
    }

    func resume() {
        playerNode?.play()
        startTimeUpdates()
    }

    func stop() {
        stopTimeUpdates()
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        eqNode = nil
        timePitchNode = nil
        audioFile = nil
        isActive = false
        currentTime = 0
        fileDuration = 0
        seekFrameOffset = 0
        totalFrames = 0
    }

    /// Seek to a specific time in seconds
    func seek(to time: TimeInterval) {
        guard let player = playerNode, let file = audioFile, isActive else { return }

        let targetFrame = AVAudioFramePosition(time * fileSampleRate)
        let clampedFrame = max(0, min(targetFrame, totalFrames))
        let remaining = AVAudioFrameCount(totalFrames - clampedFrame)
        guard remaining > 0 else { return }

        let wasPlaying = player.isPlaying
        player.stop()

        seekFrameOffset = clampedFrame
        file.framePosition = clampedFrame
        player.scheduleSegment(
            file, startingFrame: clampedFrame, frameCount: remaining,
            at: nil
        ) { [weak self] in
            Task { @MainActor in self?.handlePlaybackComplete() }
        }

        currentTime = time
        if wasPlaying { player.play() }
    }

    /// Set effective volume on the audio engine output
    func setVolume(_ volume: Float) {
        audioEngine?.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    /// Apply preset gains
    func applyPreset(_ preset: EQPreset) {
        currentPresetId = preset.id
        customGains = preset.gains
        applyGains()
    }

    /// Update individual band gain
    func setGain(_ gain: Float, forBand index: Int) {
        guard index >= 0, index < 10 else { return }
        customGains[index] = gain
        currentPresetId = "custom"
        applyGains()
    }

    /// Update playback rate on the TimePitch node
    func setRate(_ rate: Float) {
        timePitchNode?.rate = rate
    }

    /// Apply current gains to EQ node
    private func applyGains() {
        guard let eq = eqNode else { return }
        for (i, gain) in customGains.enumerated() where i < 10 {
            eq.bands[i].gain = gain
        }
    }

    // MARK: - Time Tracking

    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func updateCurrentTime() {
        guard let player = playerNode, player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return }
        let framePlayed = playerTime.sampleTime
        let totalPlayed = seekFrameOffset + framePlayed
        currentTime = Double(totalPlayed) / fileSampleRate
    }

    private func handlePlaybackComplete() {
        guard isActive else { return }
        stopTimeUpdates()
        onTrackEnd?()
    }

    // MARK: - Custom Presets

    /// Save custom preset to UserDefaults
    func saveCustomPreset(name: String) {
        var presets = loadCustomPresets()
        presets[name] = customGains
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: "customEQPresets")
        }
    }

    /// Load custom presets from UserDefaults
    func loadCustomPresets() -> [String: [Float]] {
        guard let data = UserDefaults.standard.data(forKey: "customEQPresets"),
              let presets = try? JSONDecoder().decode([String: [Float]].self, from: data)
        else { return [:] }
        return presets
    }
}
