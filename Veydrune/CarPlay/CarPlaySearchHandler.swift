#if os(iOS)
import CarPlay

final class CarPlaySearchHandler: NSObject, CPSearchTemplateDelegate {
    private var currentSearchTask: Task<Void, Never>?

    /// C5: Cancel any in-flight search task on disconnect
    func cancel() {
        currentSearchTask?.cancel()
        currentSearchTask = nil
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                         updatedSearchText searchText: String,
                         completionHandler: @escaping ([CPListItem]) -> Void) {
        currentSearchTask?.cancel()

        guard searchText.count >= 2 else {
            completionHandler([])
            return
        }

        currentSearchTask = Task { @MainActor in
            do {
                let client = AppState.shared.subsonicClient
                let results = try await client.search(query: searchText, songCount: 10)
                guard !Task.isCancelled else {
                    completionHandler([])
                    return
                }
                let songs = results.song ?? []
                let items = songs.map { song in
                    let item = CPListItem(
                        text: song.title,
                        detailText: "\(song.artist ?? "") — \(song.album ?? "")")
                    item.handler = { _, completion in
                        AudioEngine.shared.play(song: song, from: songs,
                                                at: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                        completion()
                    }
                    return item
                }
                completionHandler(items)
            } catch {
                completionHandler([])
            }
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                         selectedResult item: CPListItem,
                         completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
#endif
