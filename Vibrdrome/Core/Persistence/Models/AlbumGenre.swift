import Foundation
import SwiftData

@Model
final class AlbumGenre {
    #Index<AlbumGenre>([\.name])

    var name: String
    var album: CachedAlbum?

    init(name: String) {
        self.name = name
    }
}
