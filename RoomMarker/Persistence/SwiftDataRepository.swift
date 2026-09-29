import SwiftData

@MainActor
final class SwiftDataRepository: RoomMarkerRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save() throws {
        try context.save()
    }

    func deleteAreaPreservingContents(_ area: Area) throws {
        let rooms = Array(area.rooms)
        let tracks = Array(area.tracks)

        for room in rooms {
            room.area = nil
        }
        for track in tracks {
            track.area = nil
        }

        context.delete(area)
        try context.save()
    }

    func deleteRoom(_ room: Room) throws {
        context.delete(room)
        try context.save()
    }

    func deleteTrack(_ track: Track) throws {
        context.delete(track)
        try context.save()
    }
}
