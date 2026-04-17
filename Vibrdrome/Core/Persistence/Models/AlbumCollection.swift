import Foundation
import SwiftData

@Model
final class AlbumCollection {
    @Attribute(.unique) var id: String = UUID().uuidString
    var name: String = ""
    var listType: String = "alphabeticalByName"
    var genre: String?
    var fromYear: Int?
    var toYear: Int?
    var order: Int = 0
    var createdAt: Date = Date()

    init(name: String, listType: AlbumListType, genre: String? = nil,
         fromYear: Int? = nil, toYear: Int? = nil, order: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.listType = listType.rawValue
        self.genre = genre
        self.fromYear = fromYear
        self.toYear = toYear
        self.order = order
        self.createdAt = Date()
    }

    var albumListType: AlbumListType {
        AlbumListType(rawValue: listType) ?? .alphabeticalByName
    }
}
