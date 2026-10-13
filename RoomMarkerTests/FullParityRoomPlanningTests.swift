import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Full parity room generation", .serialized)
@MainActor
struct FullParityRoomPlanningTests {
    @Test("Classroom nodes generate rooms once and retain a historical binding")
    func generateOnce() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Synthetic Building", createdAt: 1)
        let track = Track(name: "Synthetic Track", startedAt: 1_000, endedAt: 2_000,
                          isGlobalRecording: true)
        let node = TrackTag(track: track, timeMs: 1_500, tagType: .classroom,
                            note: "T101", latitude: 22.3, longitude: 114.1,
                            altitude: 12, accuracy: 3, pressureHpa: 1_008,
                            createdAt: 1_500, areaID: area.id,
                            areaStateRawValue: "assigned", floor: "2F",
                            recordKindRawValue: "node")
        context.insert(area)
        context.insert(track)
        context.insert(node)
        try context.save()

        let preview = TrackRoomPlanner.drafts(for: track, areas: [area], rooms: [])
        let draft = try #require(preview.first)
        #expect(preview.count == 1)
        #expect(draft.name == "T101" && draft.floor == "2F")

        let created = try TrackRoomGenerationStore(context: context).create(preview, for: track)
        let room = try #require(created.first)
        #expect(created.count == 1 && room.area?.id == area.id)
        #expect(room.name == "T101" && room.floor == "2/F")
        #expect(room.latitude == 22.3 && room.longitude == 114.1)
        #expect(node.roomID == room.id && node.roomNameSnapshot == "T101")
        #expect(TrackRoomPlanner.drafts(for: track, areas: [area], rooms: created).isEmpty)
    }

    @Test("Legacy tags, non-classroom nodes, assigned rooms and duplicate names are never generated")
    func eligibleOnly() throws {
        let area = Area(name: "Synthetic Building", createdAt: 1)
        let track = Track(name: "Synthetic Track", startedAt: 1, endedAt: 10)
        let existing = Room(name: "T101", area: area, createdAt: 1)
        let cases: [(TrackTagType, String, String)] = [
            (.classroom, "T101", "node"),
            (.door, "Door", "node"),
            (.classroom, "Legacy", "legacy"),
        ]
        for (index, value) in cases.enumerated() {
            let tag = TrackTag(track: track, timeMs: Int64(index + 2), tagType: value.0,
                               note: value.1, createdAt: Int64(index + 2), areaID: area.id,
                               areaStateRawValue: "assigned", floor: "1F",
                               recordKindRawValue: value.2)
            track.tags.append(tag)
        }
        #expect(TrackRoomPlanner.drafts(for: track, areas: [area], rooms: [existing]).isEmpty)
    }

    @Test("A changed catalog invalidates the preview without partial creation")
    func stalePreview() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Synthetic Building", createdAt: 1)
        let track = Track(name: "Synthetic Track", startedAt: 1, endedAt: 10)
        let node = TrackTag(track: track, timeMs: 2, tagType: .classroom, note: "T101",
                            createdAt: 2, areaID: area.id, areaStateRawValue: "assigned",
                            floor: "1F", recordKindRawValue: "node")
        context.insert(area); context.insert(track); context.insert(node)
        try context.save()
        let preview = TrackRoomPlanner.drafts(for: track, areas: [area], rooms: [])
        let conflicting = Room(name: "T101", area: area, createdAt: 3)
        context.insert(conflicting)
        try context.save()

        #expect(throws: TrackRoomPlanningError.stalePreview) {
            try TrackRoomGenerationStore(context: context).create(preview, for: track)
        }
        #expect(try context.fetch(FetchDescriptor<Room>()).map(\.id) == [conflicting.id])
        #expect(node.roomID == nil)
    }
}
