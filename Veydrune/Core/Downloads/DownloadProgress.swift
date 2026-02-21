import Foundation
import Observation

@Observable
@MainActor
final class DownloadProgress {
    static let shared = DownloadProgress()

    var progressBySongId: [String: Double] = [:]

    func update(songId: String, progress: Double) {
        progressBySongId[songId] = progress
    }

    func remove(songId: String) {
        progressBySongId.removeValue(forKey: songId)
    }

    func progress(for songId: String) -> Double {
        progressBySongId[songId] ?? 0
    }

    func clear() {
        progressBySongId.removeAll()
    }
}
