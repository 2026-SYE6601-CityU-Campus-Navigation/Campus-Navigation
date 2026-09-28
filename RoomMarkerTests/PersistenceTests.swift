import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("SwiftData persistence")
@MainActor
struct PersistenceTests {
    @Test("All seven models and relationships persist")
    func allModelsPersist() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let timestamp: Int64 = 1_700_000_000_000

        let area = Area(name: "Synthetic Area", createdAt: timestamp)
        let room = Room(
            name: "Synthetic Room",
            area: area,
            latitude: 0,
            longitude: 0,
            altitude: 12.5,
            pressureHpa: 1008.2,
            createdAt: timestamp
        )
        let marker = Marker(
            room: room,
            name: "Synthetic Door",
            markerType: .frontDoor,
            accuracy: 3.5,
            magneticX: 1.1,
            magneticY: 2.2,
            magneticZ: 3.3,
            createdAt: timestamp
        )
        let track = Track(
            name: "Synthetic Track",
            area: area,
            startedAt: timestamp,
            endedAt: timestamp + 5_000
        )
        let point = TrackPoint(
            track: track,
            timeMs: timestamp + 1_000,
            pressureHpa: 1007.9,
            headingDeg: 45,
            wifiAvailability: .unsupported
        )
        let tag = TrackTag(
            track: track,
            timeMs: timestamp + 2_000,
            tagType: .door,
            note: "Synthetic tag",
            createdAt: timestamp + 2_000
        )
        let photo = TrackPhoto(
            track: track,
            timeMs: timestamp + 3_000,
            filePath: "photos/synthetic/1700000003000.jpg",
            note: "Synthetic photo",
            createdAt: timestamp + 3_000
        )

        context.insert(area)
        context.insert(room)
        context.insert(marker)
        context.insert(track)
        context.insert(point)
        context.insert(tag)
        context.insert(photo)
        try context.save()

        let areas = try context.fetch(FetchDescriptor<Area>())
        let rooms = try context.fetch(FetchDescriptor<Room>())
        let markers = try context.fetch(FetchDescriptor<Marker>())
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let points = try context.fetch(FetchDescriptor<TrackPoint>())
        let tags = try context.fetch(FetchDescriptor<TrackTag>())
        let photos = try context.fetch(FetchDescriptor<TrackPhoto>())

        #expect(areas.count == 1)
        #expect(rooms.count == 1)
        #expect(markers.count == 1)
        #expect(tracks.count == 1)
        #expect(points.count == 1)
        #expect(tags.count == 1)
        #expect(photos.count == 1)
        #expect(areas.first?.rooms.count == 1)
        #expect(areas.first?.tracks.count == 1)
        #expect(rooms.first?.markers.count == 1)
        #expect(tracks.first?.points.count == 1)
        #expect(tracks.first?.tags.count == 1)
        #expect(tracks.first?.photos.count == 1)
        #expect(rooms.first?.area?.id == area.id)
        #expect(tracks.first?.area?.id == area.id)
        #expect(markers.first?.room?.id == room.id)
        #expect(points.first?.track?.id == track.id)
        #expect(tags.first?.track?.id == track.id)
        #expect(photos.first?.track?.id == track.id)
        #expect(points.first?.wifiAvailability == .unsupported)
        #expect(points.first?.wifiCount == nil)
        #expect(points.first?.wifiTop == nil)
        #expect(rooms.first?.createdAt == timestamp)
        #expect(tracks.first?.startedAt == timestamp)
    }

    @Test("Deleting an area preserves rooms and tracks as unassigned")
    func deletingAreaNullifiesChildren() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Temporary Area", createdAt: 1)
        let room = Room(name: "Preserved Room", area: area, createdAt: 2)
        let track = Track(name: "Preserved Track", area: area, startedAt: 3)

        context.insert(area)
        context.insert(room)
        context.insert(track)
        try context.save()

        let repository = SwiftDataRepository(context: context)
        try repository.deleteAreaPreservingContents(area)

        #expect(try context.fetch(FetchDescriptor<Area>()).isEmpty)
        let rooms = try context.fetch(FetchDescriptor<Room>())
        let tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(rooms.count == 1)
        #expect(tracks.count == 1)
        #expect(rooms.first?.area == nil)
        #expect(tracks.first?.area == nil)
    }

    @Test("Deleting a room cascades to markers")
    func deletingRoomCascadesMarkers() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let room = Room(name: "Room", createdAt: 1)
        let marker = Marker(
            room: room,
            name: "Marker",
            markerType: .custom,
            createdAt: 2
        )
        context.insert(room)
        context.insert(marker)
        try context.save()

        let repository = SwiftDataRepository(context: context)
        try repository.deleteRoom(room)

        #expect(try context.fetch(FetchDescriptor<Room>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Marker>()).isEmpty)
    }

    @Test("Deleting a track cascades to points, tags, and photos")
    func deletingTrackCascadesChildren() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let track = Track(name: "Track", startedAt: 1)
        let point = TrackPoint(track: track, timeMs: 2)
        let tag = TrackTag(
            track: track,
            timeMs: 3,
            tagType: .stairs,
            createdAt: 3
        )
        let photo = TrackPhoto(
            track: track,
            timeMs: 4,
            filePath: "photos/synthetic.jpg",
            createdAt: 4
        )
        context.insert(track)
        context.insert(point)
        context.insert(tag)
        context.insert(photo)
        try context.save()

        let repository = SwiftDataRepository(context: context)
        try repository.deleteTrack(track)

        #expect(try context.fetch(FetchDescriptor<Track>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrackPoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
    }

    @Test("Interrupted tracks with no end time are valid")
    func interruptedTrackPersists() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let track = Track(name: "Interrupted", startedAt: 1, endedAt: nil)
        context.insert(track)
        try context.save()

        let saved = try #require(context.fetch(FetchDescriptor<Track>()).first)
        #expect(saved.endedAt == nil)
    }
}
