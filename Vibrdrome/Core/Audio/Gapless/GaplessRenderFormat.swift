import AVFoundation

/// Explicit render-format policy for the persistent gapless engine (feat/persistent-gapless-engine).
///
/// The engine graph runs at ONE stable format for the life of the engine, so consecutive tracks
/// schedule without graph reconfiguration. Sources in a different format are converted ahead of
/// playback via `AVAudioConverter` into this format (see the scheduler/prefetch pipeline).
///
/// Documented policy:
/// - Sample rate: 44_100 Hz (album-native may be selected in a later checkpoint where supported).
/// - Channels: 2 (stereo). Mono sources up-mix to stereo — this does NOT change frame count, so
///   gapless frame-accounting stays exact. Sources with >2 channels are down-mixed only via an
///   explicit converter channel map — never silently truncated.
/// - Representation: 32-bit float, non-interleaved — the mixer's native currency. No dithering is
///   applied (float has ample headroom; dithering would only matter on a final integer export).
/// - Sample-rate conversion DOES change frame count; the converted frame count is recorded per
///   segment so boundary accounting stays exact.
enum GaplessRenderFormat {
    static let sampleRate = 44_100.0
    static let channelCount: AVAudioChannelCount = 2

    /// Canonical production render format: Float32, non-interleaved, 44.1 kHz stereo.
    static let standard = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channelCount,
        interleaved: false
    )!

    /// Whether a source format can be scheduled without an `AVAudioConverter` (same SR + channel
    /// count as the running render format). Channel up-mix mono→stereo is handled by the engine
    /// connection, so only sample-rate / >target-channel mismatches require pre-conversion.
    static func needsConversion(from source: AVAudioFormat, to render: AVAudioFormat) -> Bool {
        source.sampleRate != render.sampleRate || source.channelCount > render.channelCount
    }
}
