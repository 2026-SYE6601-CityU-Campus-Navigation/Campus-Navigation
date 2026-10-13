import Foundation
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
        let areaID = area.id
        let tags = try context.fetch(FetchDescriptor<TrackTag>(
            predicate: #Predicate { $0.areaID == areaID }
        ))

        for room in rooms {
            room.area = nil
        }
        for track in tracks {
            track.legacyAreaName = track.legacyAreaName ?? area.name
            track.area = nil
        }
        for tag in tags {
            tag.areaID = nil
            tag.areaStateRawValue = "unassigned"
        }

        context.delete(area)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
