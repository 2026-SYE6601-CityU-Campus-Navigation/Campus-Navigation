import Foundation
import SwiftData

@Model
final class Area {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String
    var createdAt: Int64

    @Relationship(deleteRule: .nullify, inverse: \Room.area)
    var rooms: [Room]

    @Relationship(deleteRule: .nullify, inverse: \Track.area)
    var tracks: [Track]

    init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        createdAt: Int64
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        rooms = []
        tracks = []
    }
}
