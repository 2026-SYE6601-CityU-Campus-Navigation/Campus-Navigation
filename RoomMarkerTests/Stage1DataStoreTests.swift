import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Stage 1 cross-building data edits")
@MainActor
struct Stage1DataStoreTests {
    @Test("Deleting a building clears only its tags and preserves every track and owned photo")
    func areaDeletionPreservesCrossBuildingContents() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let a = Area(name: "Synthetic A", createdAt: 1)
        let b = Area(name: "Synthetic B", createdAt: 2)
        let track = Track(name: "Cross building", startedAt: 3, isGlobalRecording: true)
        let legacy = Track(name: "Legacy", area: a, startedAt: 2)
        let room = Room(name: "Preserved room", area: a, createdAt: 3)
        let marker = Marker(room: room, name: "Door", markerType: .frontDoor, createdAt: 4)
        let point = TrackPoint(track: track, timeMs: 5, pressureHpa: 1001, headingDeg: 0)
        let tagA = tag(track: track, area: a, time: 6)
        let tagB = tag(track: track, area: b, time: 7)
        let unknown = TrackTag(track: legacy, timeMs: 8, tagType: .door, createdAt: 8)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root)
        let bytes = Data([0xFF, 0xD8, 1, 2, 0xFF, 0xD9])
        let path = try storage.storeJPEG(bytes, trackID: track.id, timeMs: 9)
        let photo = TrackPhoto(track: track, timeMs: 9, filePath: path, note: "Preserved", createdAt: 9)
        context.insert(a)
        context.insert(b)
        context.insert(track)
        context.insert(legacy)
        context.insert(room)
        context.insert(marker)
        context.insert(point)
        context.insert(tagA)
        context.insert(tagB)
        context.insert(unknown)
        context.insert(photo)
        try context.save()

        try Phase2DataStore(context: context).deleteAreaPreservingContents(a)

        #expect(try context.fetch(FetchDescriptor<Area>()).map(\.id) == [b.id])
        #expect(try context.fetch(FetchDescriptor<Track>()).count == 2)
        #expect(track.points.count == 1 && track.tags.count == 2 && track.photos.count == 1)
        #expect(tagA.areaID == nil && tagA.areaStateRawValue == "unassigned")
        #expect(tagA.floor == "2/F")
        #expect(tagA.latitude == 1 && tagA.longitude == 2 && tagA.altitude == 3 && tagA.headingDeg == 4)
        #expect(tagA.note == "Original" && tagA.timeMs == 6 && tagA.createdAt == 6)
        #expect(tagB.areaID == b.id && tagB.areaStateRawValue == "assigned")
        #expect(unknown.areaStateRawValue == "unknown" && unknown.areaID == nil)
        #expect(room.area == nil && room.markers.first?.id == marker.id)
        #expect(legacy.area == nil && legacy.legacyAreaName == "Synthetic A")
        #expect(point.pressureHpa == 1001 && point.headingDeg == 0)
        #expect(photo.filePath == path && photo.note == "Preserved")
        #expect(SHA256.hash(data: try storage.read(relativePath: path)) == SHA256.hash(data: bytes))
        #expect(TrackAreaIndex.tracks(in: b.id, from: [track]).count == 1)
        #expect(TrackAreaIndex.unassigned(in: [track]).count == 1)
    }

    @Test("Changing tag location preserves identity, all captured fields, times and independent photos")
    func locationEditIsMetadataOnly() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let a = Area(name: "A", createdAt: 1)
        let b = Area(name: "B", createdAt: 2)
        let track = Track(name: "Track", startedAt: 1, isGlobalRecording: true)
        let tag = tag(track: track, area: a, time: 3)
        let originalID = tag.id
        let photo = TrackPhoto(track: track, timeMs: 4, filePath: "photos/synthetic.jpg", createdAt: 5)
        context.insert(a)
        context.insert(b)
        context.insert(track)
        context.insert(tag)
        context.insert(photo)
        try context.save()
        let store = Phase2DataStore(context: context)

        try store.updateTagLocation(tag, area: b, floor: " B1 ")
        #expect(tag.areaID == b.id && tag.areaStateRawValue == "assigned" && tag.floor == "B1")
        try store.updateTagLocation(tag, area: nil, floor: "")
        #expect(tag.areaID == nil && tag.areaStateRawValue == "unassigned" && tag.floor.isEmpty)
        #expect(tag.id == originalID && tag.track?.id == track.id)
        #expect(tag.timeMs == 3 && tag.createdAt == 3)
        #expect(tag.tagTypeRawValue == "门" && tag.note == "Original")
        #expect(tag.latitude == 1 && tag.longitude == 2 && tag.altitude == 3 && tag.headingDeg == 4)
        #expect(track.photos.count == 1 && track.photos.first?.id == photo.id)
        #expect(track.points.isEmpty)
    }

    @Test("Unknown legacy location changes only after an explicit user edit")
    func unknownLegacyAreaRequiresExplicitEdit() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let a = Area(name: "Legacy source", createdAt: 1)
        let track = Track(name: "Legacy", area: a, startedAt: 2)
        let tag = TrackTag(track: track, timeMs: 3, tagType: .door, createdAt: 3)
        context.insert(a)
        context.insert(track)
        context.insert(tag)
        try context.save()
        #expect(TrackAreaIndex.tracks(in: a.id, from: [track]).isEmpty)
        #expect(TrackAreaIndex.unassigned(in: [track]).isEmpty)
        try Phase2DataStore(context: context).updateTagLocation(tag, area: a, floor: "1/F")
        #expect(TrackAreaIndex.tracks(in: a.id, from: [track]).count == 1)
        #expect(track.area?.id == a.id)
    }

    private func tag(track: Track, area: Area, time: Int64) -> TrackTag {
        TrackTag(
            track: track, timeMs: time, tagType: .door, note: "Original",
            latitude: 1, longitude: 2, altitude: 3, headingDeg: 4, createdAt: time,
            areaID: area.id, areaStateRawValue: "assigned", floor: "2/F"
        )
    }
}
