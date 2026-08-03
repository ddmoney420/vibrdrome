import AVFoundation
import Foundation

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
        let channels: UInt16 = 2, bits: UInt16 = 16
        let blockAlign = channels * bits / 8
        let dataSize = UInt32(frames * Int(blockAlign))
        var data = Data(capacity: Int(dataSize) + 44)
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

        var samples = [Int16](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let value = sin(2.0 * .pi * frequency * Double(frame) / sampleRate) * 0.5
            let scaled = Int16((max(-1, min(1, value)) * 32_767).rounded())
            samples[frame * 2] = scaled
            samples[frame * 2 + 1] = scaled
        }
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        try data.write(to: url)
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
