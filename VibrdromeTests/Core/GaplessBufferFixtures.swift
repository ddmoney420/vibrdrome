import AVFoundation
import Foundation
@testable import Vibrdrome

/// Stereo 44.1 kHz fixtures for the buffer-scheduler proof.
///
/// Stereo specifically: the buffer substrate hands the graph PCM directly, so a mono fixture would
/// not exercise the production path — it would exercise a channel mismatch the converter stage has
/// yet to own. Nonisolated so Swift Testing can evaluate `arguments:` and `.enabled(if:)` without
/// crossing an actor boundary.
enum GaplessBufferFixtures {
    static let sampleRate = 44_100.0

    /// Non-harmonic so a second harmonic of one tone can never be mistaken for another tone. 440 Hz
    /// read as "playing" once when only 220 Hz was; these frequencies remove that failure mode.
    static let tones: [Double] = [233, 379, 611, 977, 1_471, 1_733, 2_129, 2_671]

    /// Write a stereo 16-bit WAV of one steady tone.
    static func writeStereoWav(url: URL, frequency: Double, frames: Int,
                               sampleRate: Double = sampleRate) throws {
        try writeWav(url: url, frequency: frequency, frames: frames, sampleRate: sampleRate,
                     channelCount: 2)
    }

    /// Write a 16-bit WAV at any rate and channel count, optionally starting at a phase offset so
    /// consecutive files form one sample-continuous signal.
    ///
    /// The phase offset is what makes a converter-continuity test meaningful: if four parts are
    /// independent tones, a boundary artifact hides inside the tone change. If they are four parts
    /// of *one* sine, any discontinuity at a join is the converter's.
    static func writeWav(url: URL, frequency: Double, frames: Int, sampleRate: Double,
                         channelCount: UInt16, phaseOffsetFrames: Int = 0,
                         declaredFrames: Int? = nil) throws {
        let channels = channelCount, bits: UInt16 = 16
        let blockAlign = channels * bits / 8
        // A declared count larger than what is written produces a file whose header promises more
        // audio than it contains — the truncated-source case.
        let dataSize = UInt32((declaredFrames ?? frames) * Int(blockAlign))
        var data = Data(capacity: frames * Int(blockAlign) + 44)
        func ascii(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        ascii("RIFF"); u32(36 + dataSize); ascii("WAVE"); ascii("fmt "); u32(16); u16(1)
        u16(channels); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * UInt32(blockAlign))
        u16(blockAlign); u16(bits)
        ascii("data"); u32(dataSize)

        var samples = [Int16](repeating: 0, count: frames * Int(channels))
        for frame in 0..<frames {
            let position = Double(frame + phaseOffsetFrames)
            let value = sin(2.0 * .pi * frequency * position / sampleRate) * 0.5
            let scaled = Int16((max(-1, min(1, value)) * 32_767).rounded())
            for channel in 0..<Int(channels) { samples[frame * Int(channels) + channel] = scaled }
        }
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        try data.write(to: url)
    }

    /// `count` files that together are one sample-continuous tone, so a join defect cannot hide
    /// behind a change of material.
    static func makeContinuousParts(count: Int, partFrames: Int, frequency: Double,
                                    sampleRate: Double, channelCount: UInt16,
                                    in directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in 0..<count {
            let url = directory.appendingPathComponent("part\(index).wav")
            try writeWav(url: url, frequency: frequency, frames: partFrames, sampleRate: sampleRate,
                         channelCount: channelCount, phaseOffsetFrames: index * partFrames)
            urls.append(url)
        }
        return urls
    }

    /// Largest absolute sample-to-sample step in a window — a click shows up here as a step far
    /// larger than a continuous tone can produce.
    static func maximumStep(_ samples: ArraySlice<Float>) -> Float {
        guard samples.count > 1 else { return 0 }
        var peak: Float = 0
        var previous = samples[samples.startIndex]
        for index in (samples.startIndex + 1)..<samples.endIndex {
            peak = max(peak, abs(samples[index] - previous))
            previous = samples[index]
        }
        return peak
    }

    /// A directory of `count` distinct stereo tone files, cycling through `tones`.
    static func makeAlbum(count: Int, frames: Int, in directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in 0..<count {
            let url = directory.appendingPathComponent("b\(index).wav")
            try writeStereoWav(url: url, frequency: tones[index % tones.count], frames: frames)
            urls.append(url)
        }
        return urls
    }

    /// Open file descriptors held by this process.
    static func openFileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }

    /// Physical footprint in bytes — the single memory metric used across the gapless work.
    static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Resident and dirty size, reported alongside footprint so a plateau is not claimed from one
    /// metric that happens to be flat.
    static func residentAndDirty() -> (resident: UInt64, dirty: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (UInt64(info.resident_size), UInt64(info.internal + info.compressed))
    }

    /// Live malloc bytes, so a footprint plateau can be checked against the heap rather than
    /// inferred from it.
    static func liveHeapBytes() -> UInt64 {
        var zone = malloc_statistics_t()
        malloc_zone_statistics(nil, &zone)
        return UInt64(zone.size_in_use)
    }
}

// MARK: - Domain readback for tests

@MainActor
extension GaplessRealTimeBackend {
    /// Live domain truth for assertions.
    ///
    /// Awaits the audio actor rather than trusting the backend's cached readout, because an
    /// assertion about resource recovery or accounting must read what the domain actually holds
    /// *now* — the cache is refreshed only after backend operations and is legitimately stale
    /// between them. A backend that never scheduled has no domain; that reads as an empty snapshot,
    /// which is exactly what "nothing allocated" should look like.
    var domainSnapshotForTesting: GaplessAudioDomainSnapshot {
        get async {
            guard let audioDomain else { return GaplessAudioDomainSnapshot() }
            return await audioDomain.snapshot()
        }
    }

    /// Live timeline truth — segments, materialized instances and the tail generation — for tests
    /// that assert on scheduling rather than resources.
    var domainReadoutForTesting: GaplessAudioDomainReadout {
        get async {
            guard let audioDomain else { return GaplessAudioDomainReadout() }
            return await audioDomain.readout()
        }
    }

    /// Schedule with the current tail generation — for tests exercising the schedule path itself
    /// rather than the supersede fence. Production callers capture the generation before their
    /// suspensions; a test calling back-to-back on the main actor has nothing suspended, so the
    /// current value is the honest one.
    @discardableResult
    func scheduleForTesting(
        _ tracks: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID, generation: UInt64)]
    ) async throws -> [GaplessScheduledSegment] {
        try await schedule(tracks, expectedTailGeneration: cachedReadout.tailGeneration)
    }
}
