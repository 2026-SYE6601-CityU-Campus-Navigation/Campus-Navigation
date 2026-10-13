import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 1 disk migrations", .serialized)
@MainActor
struct Stage1MigrationTests {
    @Test("The original V1 container shape upgrades without changing stored data or JPEG bytes")
    func originalV1StorePreservesAllModels() throws {
        try withTemporaryStore { fixture in
            // Match the released factory: it used Schema(V1.models), not
            // Schema(versionedSchema: V1.self). This exercises that actual metadata.
            try writeV1Store(fixture, usesVersionedSchema: false)
            let originalPhoto = try Data(contentsOf: fixture.photoURL)

            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
                let context = container.mainContext
                let area = try #require(context.fetch(FetchDescriptor<Area>()).first)
                let room = try #require(context.fetch(FetchDescriptor<Room>()).first)
                let marker = try #require(context.fetch(FetchDescriptor<Marker>()).first)
                let tracks = try context.fetch(FetchDescriptor<Track>())
                let track = try #require(tracks.first { $0.id == fixture.trackID })
                let interrupted = try #require(tracks.first { $0.id == fixture.interruptedTrackID })
                let points = try context.fetch(FetchDescriptor<TrackPoint>())
                let point = try #require(points.first { $0.id == fixture.pointID })
                let emptyPoint = try #require(points.first { $0.id == fixture.emptyPointID })
                let tags = try context.fetch(FetchDescriptor<TrackTag>())
                let tag = try #require(tags.first { $0.id == fixture.tagID })
                let photo = try #require(context.fetch(FetchDescriptor<TrackPhoto>()).first)

                #expect(area.id == fixture.areaID)
                #expect(area.name == "Synthetic legacy building")
                #expect(area.note == "Legacy area note")
                #expect(area.createdAt == fixture.time)
                #expect(room.id == fixture.roomID)
                #expect(room.name == "Synthetic legacy room")
                #expect(room.note == "Legacy room note")
                #expect(room.area?.id == fixture.areaID)
                #expect(room.latitude == 0)
                #expect(room.longitude == 0)
                #expect(room.altitude == 12.5)
                #expect(room.pressureHpa == 1008.2)
                #expect(room.createdAt == fixture.time + 1)
                #expect(marker.id == fixture.markerID)
                #expect(marker.room?.id == fixture.roomID)
                #expect(marker.name == "Synthetic legacy door")
                #expect(marker.markerTypeRawValue == MarkerType.frontDoor.rawValue)
                #expect(marker.latitude == 0)
                #expect(marker.longitude == 0)
                #expect(marker.altitude == 12.6)
                #expect(marker.accuracy == 3.5)
                #expect(marker.pressureHpa == 1008.1)
                #expect(marker.magneticX == 1.1)
                #expect(marker.magneticY == 2.2)
                #expect(marker.magneticZ == 3.3)
                #expect(marker.createdAt == fixture.time + 2)
                #expect(tracks.count == 2)
                #expect(track.name == "Synthetic legacy track")
                #expect(track.startedAt == fixture.time + 3)
                #expect(track.endedAt == fixture.time + 13_000)
                #expect(track.area?.id == fixture.areaID)
                #expect(track.legacyAreaName == nil)
                #expect(!track.isGlobalRecording)
                #expect(track.points.count == 2)
                #expect(track.tags.count == 2)
                #expect(track.photos.count == 1)
                #expect(interrupted.endedAt == nil)
                #expect(interrupted.area == nil)
                #expect(interrupted.points.isEmpty)
                #expect(!interrupted.isGlobalRecording)
                #expect(points.count == 2)
                #expect(point.track?.id == fixture.trackID)
                #expect(point.timeMs == fixture.time + 1_000)
                #expect(point.latitude == 0)
                #expect(point.longitude == 0)
                #expect(point.altitude == 12.7)
                #expect(point.accuracy == 4.5)
                #expect(point.pressureHpa == 1007.9)
                #expect(point.magneticX == 4.1)
                #expect(point.magneticY == 5.2)
                #expect(point.magneticZ == 6.3)
                #expect(point.headingDeg == 45)
                #expect(point.wifiAvailabilityRawValue == "unsupported")
                #expect(point.wifiCount == nil)
                #expect(point.wifiTop == nil)
                #expect(emptyPoint.timeMs == fixture.time + 10_000)
                #expect(emptyPoint.latitude == nil)
                #expect(emptyPoint.longitude == nil)
                #expect(emptyPoint.altitude == nil)
                #expect(emptyPoint.pressureHpa == nil)
                #expect(emptyPoint.headingDeg == nil)
                #expect(tags.count == 2)
                #expect(tags.allSatisfy { $0.accuracy == nil && $0.pressureHpa == nil })
                #expect(photo.accuracy == nil && photo.pressureHpa == nil)
                #expect(tag.track?.id == fixture.trackID)
                #expect(tag.timeMs == fixture.time + 2_000)
                #expect(tag.createdAt == fixture.time + 2_100)
                #expect(tag.tagTypeRawValue == TrackTagType.door.rawValue)
                #expect(tag.note == "Legacy tag note")
                #expect(tag.latitude == 0)
                #expect(tag.longitude == 0)
                #expect(tag.altitude == 12.8)
                #expect(tag.headingDeg == 90)
                #expect(tags.allSatisfy { $0.areaID == nil })
                #expect(tags.allSatisfy { $0.areaStateRawValue == "unknown" })
                #expect(tags.allSatisfy { $0.floor.isEmpty })
                #expect(tags.allSatisfy { $0.recordKindRawValue == "legacy" })
                #expect(photo.kindRawValue == "legacyUnlinked")
                #expect(photo.tagID == nil)
                #expect(photo.id == fixture.photoID)
                #expect(photo.track?.id == fixture.trackID)
                #expect(photo.filePath == fixture.photoPath)
                #expect(photo.note == "Legacy photo note")
                #expect(photo.timeMs == fixture.time + 3_000)
                #expect(photo.createdAt == fixture.time + 3_100)
                #expect(photo.latitude == 0)
                #expect(photo.longitude == 0)
                #expect(photo.altitude == 12.9)
                #expect(photo.headingDeg == 180)
            }

            let migratedPhoto = try Data(contentsOf: fixture.photoURL)
            #expect(migratedPhoto.count == originalPhoto.count)
            #expect(SHA256.hash(data: migratedPhoto) == SHA256.hash(data: originalPhoto))
            #expect(UIImage(data: migratedPhoto) != nil)
        }
    }

    @Test("An explicitly versioned V1 store also upgrades with unknown node ownership")
    func versionedV1StoreUpgrades() throws {
        try withTemporaryStore { fixture in
            try writeV1Store(fixture, usesVersionedSchema: true)
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
                let tags = try container.mainContext.fetch(FetchDescriptor<TrackTag>())
                #expect(tags.count == 2)
                #expect(tags.allSatisfy { $0.areaID == nil && $0.areaStateRawValue == "unknown" })
                #expect(tags.allSatisfy { $0.floor.isEmpty })
            }
        }
    }

    @Test("Reopening an upgraded store never backfills a user-cleared node from its legacy track")
    func repeatedOpenNeverGuessesNodeArea() throws {
        try withTemporaryStore { fixture in
            try writeV1Store(fixture, usesVersionedSchema: false)
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
                let tag = try #require(container.mainContext.fetch(FetchDescriptor<TrackTag>())
                    .first { $0.id == fixture.tagID })
                tag.areaID = fixture.areaID
                tag.areaStateRawValue = "assigned"
                tag.floor = "3/F"
                try container.mainContext.save()
                tag.areaID = nil
                tag.areaStateRawValue = "unassigned"
                try container.mainContext.save()
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
                    let tags = try container.mainContext.fetch(FetchDescriptor<TrackTag>())
                    let changedTag = try #require(tags.first { $0.id == fixture.tagID })
                    let unknownTag = try #require(tags.first { $0.id == fixture.unknownTagID })
                    #expect(changedTag.areaID == nil)
                    #expect(changedTag.areaStateRawValue == "unassigned")
                    #expect(changedTag.floor == "3/F")
                    #expect(unknownTag.areaID == nil)
                    #expect(unknownTag.areaStateRawValue == "unknown")
                    #expect(changedTag.track?.area?.id == fixture.areaID)
                }
            }
        }
    }

    @Test("A fresh current disk store retains global tracks and independently assigned tag floors")
    func freshGlobalStoreReopens() throws {
        try withTemporaryStore { fixture in
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
                let track = Track(
                    id: fixture.trackID,
                    name: "Synthetic global track",
                    startedAt: fixture.time,
                    isGlobalRecording: true,
                    legacyAreaName: "Preserved historical label"
                )
                let assigned = TrackTag(
                    id: fixture.tagID,
                    track: track,
                    timeMs: fixture.time + 1,
                    tagType: .door,
                    createdAt: fixture.time + 1,
                    areaID: fixture.areaID,
                    areaStateRawValue: "assigned",
                    floor: "LG1"
                )
                let unassigned = TrackTag(
                    id: fixture.unknownTagID,
                    track: track,
                    timeMs: fixture.time + 2,
                    tagType: .stairs,
                    createdAt: fixture.time + 2,
                    areaStateRawValue: "unassigned"
                )
                container.mainContext.insert(track)
                container.mainContext.insert(assigned)
                container.mainContext.insert(unassigned)
                try container.mainContext.save()
            }
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
                let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                let tag = try #require(track.tags.first { $0.id == fixture.tagID })
                #expect(track.id == fixture.trackID)
                #expect(track.area == nil)
                #expect(track.isGlobalRecording)
                #expect(track.legacyAreaName == "Preserved historical label")
                #expect(tag.areaID == fixture.areaID)
                #expect(tag.areaStateRawValue == "assigned")
                #expect(tag.floor == "LG1")
                #expect(track.tags.first { $0.id == fixture.unknownTagID }?.areaStateRawValue == "unassigned")
            }
        }
    }

    @Test("An unreadable store propagates failure without resetting its file or touching photos")
    func failedOpenNeverResetsData() throws {
        try withTemporaryStore { fixture in
            let invalidStore = Data("synthetic non-SQLite store".utf8)
            try invalidStore.write(to: fixture.storeURL)
            let originalPhoto = try Data(contentsOf: fixture.photoURL)
            #expect(throws: (any Error).self) {
                _ = try RoomMarkerModelContainer.make(storeURL: fixture.storeURL)
            }
            #expect(try Data(contentsOf: fixture.storeURL) == invalidStore)
            #expect(try Data(contentsOf: fixture.photoURL) == originalPhoto)
        }
    }

    @Test("An explicit disk URL cannot silently override an in-memory request")
    func conflictingStorageConfigurationRejected() {
        #expect(throws: RoomMarkerStoreConfigurationError.self) {
            _ = try RoomMarkerModelContainer.make(
                inMemory: true,
                storeURL: URL(fileURLWithPath: "/synthetic/not-opened.store")
            )
        }
    }

    private func writeV1Store(_ fixture: MigrationFixture, usesVersionedSchema: Bool) throws {
        try autoreleasepool {
            let schema = usesVersionedSchema
                ? Schema(versionedSchema: RoomMarkerSchemaV1.self)
                : Schema(RoomMarkerSchemaV1.models)
            let configuration = ModelConfiguration("RoomMarker", schema: schema, url: fixture.storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: ReleasedV1MigrationPlan.self,
                configurations: configuration
            )
            let context = container.mainContext
            let area = RoomMarkerSchemaV1.Area(
                id: fixture.areaID, name: "Synthetic legacy building",
                note: "Legacy area note", createdAt: fixture.time
            )
            let room = RoomMarkerSchemaV1.Room(
                id: fixture.roomID, name: "Synthetic legacy room", note: "Legacy room note", area: area,
                latitude: 0, longitude: 0, altitude: 12.5, pressureHpa: 1008.2,
                createdAt: fixture.time + 1
            )
            let marker = RoomMarkerSchemaV1.Marker(
                id: fixture.markerID, room: room, name: "Synthetic legacy door", markerType: .frontDoor,
                latitude: 0, longitude: 0, altitude: 12.6, accuracy: 3.5, pressureHpa: 1008.1,
                magneticX: 1.1, magneticY: 2.2, magneticZ: 3.3, createdAt: fixture.time + 2
            )
            let track = RoomMarkerSchemaV1.Track(
                id: fixture.trackID, name: "Synthetic legacy track", area: area,
                startedAt: fixture.time + 3, endedAt: fixture.time + 13_000
            )
            let interrupted = RoomMarkerSchemaV1.Track(
                id: fixture.interruptedTrackID, name: "Synthetic interrupted track",
                startedAt: fixture.time + 20_000
            )
            let point = RoomMarkerSchemaV1.TrackPoint(
                id: fixture.pointID, track: track, timeMs: fixture.time + 1_000,
                latitude: 0, longitude: 0, altitude: 12.7, accuracy: 4.5, pressureHpa: 1007.9,
                magneticX: 4.1, magneticY: 5.2, magneticZ: 6.3, headingDeg: 45
            )
            let emptyPoint = RoomMarkerSchemaV1.TrackPoint(
                id: fixture.emptyPointID, track: track, timeMs: fixture.time + 10_000
            )
            let tag = RoomMarkerSchemaV1.TrackTag(
                id: fixture.tagID, track: track, timeMs: fixture.time + 2_000, tagType: .door,
                note: "Legacy tag note", latitude: 0, longitude: 0, altitude: 12.8,
                headingDeg: 90, createdAt: fixture.time + 2_100
            )
            let unknownTag = RoomMarkerSchemaV1.TrackTag(
                id: fixture.unknownTagID, track: track, timeMs: fixture.time + 2_500,
                tagType: .stairs, createdAt: fixture.time + 2_500
            )
            let photo = RoomMarkerSchemaV1.TrackPhoto(
                id: fixture.photoID, track: track, timeMs: fixture.time + 3_000,
                filePath: fixture.photoPath, note: "Legacy photo note", latitude: 0, longitude: 0,
                altitude: 12.9, headingDeg: 180, createdAt: fixture.time + 3_100
            )
            context.insert(area)
            context.insert(room)
            context.insert(marker)
            context.insert(track)
            context.insert(interrupted)
            context.insert(point)
            context.insert(emptyPoint)
            context.insert(tag)
            context.insert(unknownTag)
            context.insert(photo)
            try context.save()
        }
    }

    private func withTemporaryStore(_ test: (MigrationFixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomMarkerMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = MigrationFixture(directory: directory)
        try FileManager.default.createDirectory(
            at: fixture.photoURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        try jpeg.write(to: fixture.photoURL)
        try test(fixture)
    }
}

// Match the released factory's V1-only plan as well as its schema construction.
// No ModelContainer, ModelContext or managed model escapes writeV1Store's pool.
private enum ReleasedV1MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoomMarkerSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

private struct MigrationFixture {
    let directory: URL
    let areaID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let roomID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    let markerID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
    let trackID = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
    let interruptedTrackID = UUID(uuidString: "10000000-0000-4000-8000-000000000005")!
    let pointID = UUID(uuidString: "10000000-0000-4000-8000-000000000006")!
    let emptyPointID = UUID(uuidString: "10000000-0000-4000-8000-000000000007")!
    let tagID = UUID(uuidString: "10000000-0000-4000-8000-000000000008")!
    let unknownTagID = UUID(uuidString: "10000000-0000-4000-8000-000000000009")!
    let photoID = UUID(uuidString: "10000000-0000-4000-8000-00000000000a")!
    let time: Int64 = 1_700_000_000_000

    var storeURL: URL { directory.appendingPathComponent("RoomMarker.store") }
    var photoPath: String { "photos/\(trackID.uuidString.lowercased())/legacy.jpg" }
    var photoURL: URL { directory.appendingPathComponent(photoPath) }
}
