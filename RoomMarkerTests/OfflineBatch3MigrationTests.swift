import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Offline batch 3 V6 catalog migration", .serialized)
@MainActor
struct OfflineBatch3MigrationTests {
    @Test("V6 to V7 preserves ten models and quality; never infers catalog or room bindings")
    func v6Upgrade() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let areaID = UUID(), roomID = UUID(), markerID = UUID(), trackID = UUID(), interruptedID = UUID()
            let pointID = UUID(), nodeID = UUID(), legacyTagID = UUID(), photoID = UUID(), legacyPhotoID = UUID()
            let firstID = UUID(), secondID = UUID(), cornerID = UUID(), batchID = UUID()
            let samples = [RawIMUSample(kind: .accelerometer, sensorTimeSeconds: 101, timeMs: 2000, receivedAtMs: 2100,
                                       segmentID: firstID, x: 0, y: 0, z: -1),
                           RawIMUSample(kind: .gyroscope, sensorTimeSeconds: 101.02, timeMs: 2020, receivedAtMs: 2110,
                                       segmentID: firstID, x: 0.1, y: 0.2, z: 0.3)]
            let payload = try JSONEncoder().encode(samples)
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let nodePath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 2500)
            let legacyPath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 3500)
            for path in [nodePath, legacyPath] { try photos.confirmReferenced(relativePath: path) }
            try autoreleasepool {
                let schema = Schema(versionedSchema: RoomMarkerSchemaV6.self)
                let container = try ModelContainer(
                    for: schema, migrationPlan: Batch3V6ReleasedPlan.self,
                    configurations: ModelConfiguration("RoomMarker", schema: schema, url: url)
                )
                let context = container.mainContext
                let area = RoomMarkerSchemaV6.Area(id: areaID, name: "Synthetic A", note: "area", createdAt: 1)
                let room = RoomMarkerSchemaV6.Room(id: roomID, name: "Synthetic room", note: "room", area: area,
                                                 latitude: 0, longitude: 0, altitude: 12, pressureHpa: 1008, createdAt: 2)
                let marker = RoomMarkerSchemaV6.Marker(id: markerID, room: room, name: "Synthetic door", markerType: .frontDoor,
                                                     latitude: 0, longitude: 0, altitude: 12, accuracy: 3, pressureHpa: 1008,
                                                     magneticX: 1, magneticY: 2, magneticZ: 3, createdAt: 3)
                let track = RoomMarkerSchemaV6.Track(id: trackID, name: "Synthetic V6", startedAt: 1000, endedAt: 5000,
                                                   isGlobalRecording: true, legacyAreaName: "Historical hint")
                track.isSegmentedRecording = true
                track.rawIMURequested = true
                track.rawIMUInterval = 0.02
                track.rawAccelState = "stopped"
                track.rawGyroState = "stopped"
                let interrupted = RoomMarkerSchemaV6.Track(id: interruptedID, name: "Interrupted V6", area: area, startedAt: 6000)
                context.insert(area)
                context.insert(room)
                context.insert(marker)
                context.insert(track)
                context.insert(interrupted)
                context.insert(RoomMarkerSchemaV6.TrackSegment(id: firstID, track: track, ordinal: 0, startedAt: 1000,
                                                               endedAt: 3000, environment: .indoor))
                context.insert(RoomMarkerSchemaV6.TrackSegment(id: secondID, track: track, ordinal: 1, startedAt: 3000,
                                                               endedAt: 5000, environment: .outdoor))
                context.insert(RoomMarkerSchemaV6.TrackPoint(id: pointID, track: track, timeMs: 2000, latitude: 0, longitude: 0,
                                                             altitude: 12, accuracy: 3, pressureHpa: 1008,
                                                             magneticX: 1, magneticY: 2, magneticZ: 3, headingDeg: 90,
                                                             segmentID: firstID))
                let corner = TrackPointDraft(timeMs: 2200, latitude: nil, longitude: nil, altitude: 12,
                                             accuracy: nil, pressureHpa: nil, magneticX: nil, magneticY: nil,
                                             magneticZ: nil, headingDeg: nil, wifiAvailability: .unsupported,
                                             wifiCount: nil, wifiTop: nil, segmentID: firstID)
                context.insert(RoomMarkerSchemaV6.TrackCorner(id: cornerID, track: track, sample: corner, note: "Synthetic turn"))
                context.insert(RoomMarkerSchemaV6.TrackTag(id: nodeID, track: track, timeMs: 2500, tagType: .mainGate,
                                                           note: "node", headingDeg: 90, accuracy: 3.25, pressureHpa: 1007.75, createdAt: 2600, areaID: areaID,
                                                           areaStateRawValue: "assigned", floor: "B1", recordKindRawValue: "node"))
                context.insert(RoomMarkerSchemaV6.TrackTag(id: legacyTagID, track: track, timeMs: 3500,
                                                           tagType: .stairs, note: "legacy", createdAt: 3600))
                context.insert(RoomMarkerSchemaV6.TrackPhoto(id: photoID, track: track, timeMs: 2500, filePath: nodePath,
                                                             note: "node", headingDeg: 90, accuracy: 3.25, pressureHpa: 1007.75, createdAt: 2600,
                                                             kindRawValue: "node", tagID: nodeID))
                context.insert(RoomMarkerSchemaV6.TrackPhoto(id: legacyPhotoID, track: track, timeMs: 3500,
                                                             filePath: legacyPath, note: "legacy", createdAt: 3600))
                let batch = RoomMarkerSchemaV6.TrackIMUBatch(id: batchID, samples: samples, payload: payload)
                context.insert(batch)
                batch.track = track
                try context.save()
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let context = container.mainContext
                    let area = try #require(context.fetch(FetchDescriptor<Area>()).first)
                    let room = try #require(context.fetch(FetchDescriptor<Room>()).first)
                    #expect(area.category.isEmpty && area.catalogKey == nil)
                    #expect(room.code.isEmpty && room.floor.isEmpty && room.catalogKey == nil)
                    let marker = try #require(context.fetch(FetchDescriptor<Marker>()).first)
                    let tracks = try context.fetch(FetchDescriptor<Track>())
                    let track = try #require(tracks.first { $0.id == trackID })
                    let interrupted = try #require(tracks.first { $0.id == interruptedID })
                    #expect(area.id == areaID && area.name == "Synthetic A" && area.note == "area")
                    #expect(room.id == roomID && room.area?.id == areaID && room.latitude == 0 && room.pressureHpa == 1008)
                    #expect(marker.id == markerID && marker.room?.id == roomID && marker.magneticZ == 3)
                    #expect(track.startedAt == 1000 && track.endedAt == 5000 && track.legacyAreaName == "Historical hint")
                    #expect(track.isGlobalRecording && track.isSegmentedRecording)
                    let segments = TrackSegmentRules.ordered(in: track)
                    #expect(segments.map(\.id) == [firstID, secondID])
                    #expect(segments.map(\.startedAt) == [1000, 3000] && segments.map(\.endedAt) == [3000, 5000])
                    #expect(segments.map(\.environmentRawValue) == ["indoor", "outdoor"])
                    let point = try #require(track.points.first)
                    #expect(point.id == pointID && point.timeMs == 2000 && point.segmentID == firstID)
                    #expect(point.latitude == 0 && point.headingDeg == 90 && point.wifiCount == nil && point.wifiTop == nil)
                    let corner = try #require(track.corners.first)
                    #expect(corner.id == cornerID && corner.segmentID == firstID && corner.timeMs == 2200)
                    #expect(corner.note == "Synthetic turn" && corner.altitude == 12)
                    let node = try #require(track.tags.first { $0.id == nodeID })
                    let photo = try NodePhotoAssociation.photo(for: node)
                    #expect(node.accuracy == 3.25 && node.pressureHpa == 1007.75)
                    #expect(track.tags.allSatisfy { $0.roomID == nil && $0.roomNameSnapshot == nil && $0.roomCodeSnapshot == nil && $0.roomDoorRole == nil })
                    #expect(node.tagType == .mainGate && node.areaID == areaID && node.floor == "B1" && node.headingDeg == 90)
                    #expect(photo.id == photoID && photo.filePath == nodePath && photo.tagID == nodeID)
                    #expect(track.tags.first { $0.id == legacyTagID }?.recordKindRawValue == "legacy")
                    #expect(track.photos.first { $0.id == legacyPhotoID }?.kindRawValue == "legacyUnlinked")
                    #expect(track.photos.first { $0.id == legacyPhotoID }?.tagID == nil)
                    #expect(interrupted.endedAt == nil && interrupted.area?.id == areaID && interrupted.segments.isEmpty)
                    #expect(track.rawIMURequested && track.rawIMUInterval == 0.02)
                    #expect(track.rawAccelState == "stopped" && track.rawGyroState == "stopped")
                    let batch = try #require(track.imuBatches.first)
                    #expect(track.imuBatches.count == 1 && batch.id == batchID && batch.track?.id == trackID)
                    #expect(batch.payload == payload && batch.sampleCount == 2)
                    #expect(try batch.decodedSamples() == samples)
                    #expect(!interrupted.rawIMURequested && interrupted.imuBatches.isEmpty)
                    let exported = try ExportV3SnapshotBuilder(photoStorage: photos).build(tracks: tracks, exportedAt: 7000)
                    let dto = try #require(exported.tracks.first { $0.id == trackID.uuidString.lowercased() })
                    #expect(dto.tags.first { $0.id == nodeID.uuidString.lowercased() }?.accuracy == 3.25)
                    #expect(dto.tags.first { $0.id == legacyTagID.uuidString.lowercased() }?.pressureHpa == nil)
                    #expect(dto.tags.allSatisfy { $0.roomBinding == nil })
                    #expect(dto.photos.first { $0.id == photoID.uuidString.lowercased() }?.pressureHpa == 1007.75)
                    #expect(dto.photos.first { $0.id == legacyPhotoID.uuidString.lowercased() }?.accuracy == nil)
                    #expect(dto.imu.sampleCount == 2 && dto.corners.count == 1 && dto.segments.count == 2)
                    #expect(!context.hasChanges)
                    for path in [nodePath, legacyPath] {
                        let bytes = try photos.read(relativePath: path)
                        #expect(bytes.count == jpeg.count && SHA256.hash(data: bytes) == SHA256.hash(data: jpeg))
                        #expect(UIImage(data: bytes) != nil)
                    }
                }
            }
        }
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage6NodeMigration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func makeJPEG() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }
}

private enum Batch3V6ReleasedPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoomMarkerSchemaV1.self, RoomMarkerSchemaV2.self, RoomMarkerSchemaV3.self, RoomMarkerSchemaV4.self, RoomMarkerSchemaV5.self, RoomMarkerSchemaV6.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RoomMarkerSchemaV1.self, toVersion: RoomMarkerSchemaV2.self),
            .lightweight(fromVersion: RoomMarkerSchemaV2.self, toVersion: RoomMarkerSchemaV3.self),
            .lightweight(fromVersion: RoomMarkerSchemaV3.self, toVersion: RoomMarkerSchemaV4.self),
            .lightweight(fromVersion: RoomMarkerSchemaV4.self, toVersion: RoomMarkerSchemaV5.self),
            .lightweight(fromVersion: RoomMarkerSchemaV5.self, toVersion: RoomMarkerSchemaV6.self),
        ]
    }
}
