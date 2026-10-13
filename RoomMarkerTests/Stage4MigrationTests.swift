import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 4 disk migrations", .serialized)
@MainActor
struct Stage4MigrationTests {
    @Test("V4 upgrade preserves all nine model kinds, segments, node linkage, legacy media and JPEG hashes")
    func v4Upgrade() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let areaID = UUID(), roomID = UUID(), markerID = UUID(), trackID = UUID(), interruptedID = UUID()
            let pointID = UUID(), nodeID = UUID(), legacyTagID = UUID(), photoID = UUID(), legacyPhotoID = UUID()
            let firstID = UUID(), secondID = UUID(), cornerID = UUID()
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let nodePath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 2500)
            let legacyPath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 3500)
            for path in [nodePath, legacyPath] { try photos.confirmReferenced(relativePath: path) }
            try autoreleasepool {
                let schema = Schema(versionedSchema: RoomMarkerSchemaV4.self)
                let container = try ModelContainer(
                    for: schema, migrationPlan: Stage3ReleasedPlan.self,
                    configurations: ModelConfiguration("RoomMarker", schema: schema, url: url)
                )
                let context = container.mainContext
                let area = RoomMarkerSchemaV4.Area(id: areaID, name: "Synthetic A", note: "area", createdAt: 1)
                let room = RoomMarkerSchemaV4.Room(id: roomID, name: "Synthetic room", note: "room", area: area,
                                                 latitude: 0, longitude: 0, altitude: 12, pressureHpa: 1008, createdAt: 2)
                let marker = RoomMarkerSchemaV4.Marker(id: markerID, room: room, name: "Synthetic door", markerType: .frontDoor,
                                                     latitude: 0, longitude: 0, altitude: 12, accuracy: 3, pressureHpa: 1008,
                                                     magneticX: 1, magneticY: 2, magneticZ: 3, createdAt: 3)
                let track = RoomMarkerSchemaV4.Track(id: trackID, name: "Synthetic V4", startedAt: 1000, endedAt: 5000,
                                                   isGlobalRecording: true, legacyAreaName: "Historical hint")
                track.isSegmentedRecording = true
                let interrupted = RoomMarkerSchemaV4.Track(id: interruptedID, name: "Interrupted V4", area: area, startedAt: 6000)
                context.insert(area)
                context.insert(room)
                context.insert(marker)
                context.insert(track)
                context.insert(interrupted)
                context.insert(RoomMarkerSchemaV4.TrackSegment(id: firstID, track: track, ordinal: 0, startedAt: 1000,
                                                               endedAt: 3000, environment: .indoor))
                context.insert(RoomMarkerSchemaV4.TrackSegment(id: secondID, track: track, ordinal: 1, startedAt: 3000,
                                                               endedAt: 5000, environment: .outdoor))
                context.insert(RoomMarkerSchemaV4.TrackPoint(id: pointID, track: track, timeMs: 2000, latitude: 0, longitude: 0,
                                                             altitude: 12, accuracy: 3, pressureHpa: 1008,
                                                             magneticX: 1, magneticY: 2, magneticZ: 3, headingDeg: 90,
                                                             segmentID: firstID))
                let corner = TrackPointDraft(timeMs: 2200, latitude: nil, longitude: nil, altitude: 12,
                                             accuracy: nil, pressureHpa: nil, magneticX: nil, magneticY: nil,
                                             magneticZ: nil, headingDeg: nil, wifiAvailability: .unsupported,
                                             wifiCount: nil, wifiTop: nil, segmentID: firstID)
                context.insert(RoomMarkerSchemaV4.TrackCorner(id: cornerID, track: track, sample: corner, note: "Synthetic turn"))
                context.insert(RoomMarkerSchemaV4.TrackTag(id: nodeID, track: track, timeMs: 2500, tagType: .mainGate,
                                                           note: "node", headingDeg: 90, createdAt: 2600, areaID: areaID,
                                                           areaStateRawValue: "assigned", floor: "B1", recordKindRawValue: "node"))
                context.insert(RoomMarkerSchemaV4.TrackTag(id: legacyTagID, track: track, timeMs: 3500,
                                                           tagType: .stairs, note: "legacy", createdAt: 3600))
                context.insert(RoomMarkerSchemaV4.TrackPhoto(id: photoID, track: track, timeMs: 2500, filePath: nodePath,
                                                             note: "node", headingDeg: 90, createdAt: 2600,
                                                             kindRawValue: "node", tagID: nodeID))
                context.insert(RoomMarkerSchemaV4.TrackPhoto(id: legacyPhotoID, track: track, timeMs: 3500,
                                                             filePath: legacyPath, note: "legacy", createdAt: 3600))
                try context.save()
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let context = container.mainContext
                    let area = try #require(context.fetch(FetchDescriptor<Area>()).first)
                    let room = try #require(context.fetch(FetchDescriptor<Room>()).first)
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
                    #expect(track.tags.allSatisfy { $0.accuracy == nil && $0.pressureHpa == nil })
                    #expect(track.photos.allSatisfy { $0.accuracy == nil && $0.pressureHpa == nil })
                    #expect(node.tagType == .mainGate && node.areaID == areaID && node.floor == "B1" && node.headingDeg == 90)
                    #expect(photo.id == photoID && photo.filePath == nodePath && photo.tagID == nodeID)
                    #expect(track.tags.first { $0.id == legacyTagID }?.recordKindRawValue == "legacy")
                    #expect(track.photos.first { $0.id == legacyPhotoID }?.kindRawValue == "legacyUnlinked")
                    #expect(track.photos.first { $0.id == legacyPhotoID }?.tagID == nil)
                    #expect(interrupted.endedAt == nil && interrupted.area?.id == areaID && interrupted.segments.isEmpty)
                    for item in tracks {
                        #expect(!item.rawIMURequested && item.rawIMUInterval == nil && item.imuBatches.isEmpty)
                        #expect(item.rawAccelState == "notRequested" && item.rawGyroState == "notRequested" && item.rawIMURejectedCount == 0)
                    }
                    #expect(try context.fetch(FetchDescriptor<TrackIMUBatch>()).isEmpty)
                    for path in [nodePath, legacyPath] {
                        let bytes = try photos.read(relativePath: path)
                        #expect(bytes.count == jpeg.count && SHA256.hash(data: bytes) == SHA256.hash(data: jpeg))
                        #expect(UIImage(data: bytes) != nil)
                    }
                }
            }
        }
    }

    @Test("V5 disk roundtrip retains raw payload, statuses, units and segment membership without catch-up")
    func currentRoundtrip() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let batchID = UUID()
            var trackID: UUID?, segmentID: UUID?, originalPayload: Data?
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let store = SwiftDataRecordingStore(context: container.mainContext)
                let track = try store.createSegmentedTrack(name: "Interrupted raw", startedAt: 1000, environment: .indoor, collectRawIMU: true)
                trackID = track.id
                segmentID = try TrackSegmentRules.current(in: track).id
                let samples = [RawIMUSample(kind: .accelerometer, sensorTimeSeconds: 101, timeMs: 2000, receivedAtMs: 2100,
                                            segmentID: try #require(segmentID), x: 0, y: 0, z: -1),
                               RawIMUSample(kind: .gyroscope, sensorTimeSeconds: 101.02, timeMs: 2020, receivedAtMs: 2110,
                                            segmentID: try #require(segmentID), x: 0.1, y: -0.2, z: 0.3)]
                try store.saveIMU(id: batchID, samples: samples,
                                  status: .init(accelerometer: .receiving, gyroscope: .receiving, rejectedCount: 2), for: track)
                originalPayload = track.imuBatches.first?.payload
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                    let batch = try #require(track.imuBatches.first)
                    #expect(track.id == trackID && track.endedAt == nil && track.rawIMURequested && track.rawIMUInterval == 0.02)
                    #expect(track.rawAccelState == "receiving" && track.rawGyroState == "receiving" && track.rawIMURejectedCount == 2)
                    #expect(track.segments.first?.id == segmentID && track.segments.first?.endedAt == nil)
                    #expect(batch.id == batchID && batch.payload == originalPayload && batch.sampleCount == 2)
                    #expect(batch.accelerationCount == 1 && batch.gyroscopeCount == 1)
                    let samples = try batch.decodedSamples()
                    #expect(samples.map(\.timeMs) == [2000, 2020] && samples.map(\.receivedAtMs) == [2100, 2110])
                    #expect(samples.allSatisfy { $0.segmentID == segmentID } && samples[0].z == -1 && samples[1].y == -0.2)
                    #expect(track.imuBatches.count == 1 && track.points.isEmpty && !container.mainContext.hasChanges)
                }
            }
        }
    }

    @Test("Failed IMU inserts leave no ghost batches after repeated rollback, retry and disk reopen")
    func rollbackRoundtrip() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let nodeID = UUID(), legacyTagID = UUID(), batchID = UUID()
            var paths: [String] = [], firstID: UUID?, cornerID: UUID?
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let failure = Stage4SaveFailure()
                let store = SwiftDataRecordingStore(context: container.mainContext) {
                    if failure.enabled { throw Stage4Failure.save }
                    try $0.save()
                }
                let track = try store.createSegmentedTrack(name: "Rollback", startedAt: 1000, environment: .unknown, collectRawIMU: true)
                firstID = try TrackSegmentRules.current(in: track).id
                var point = SampleAssembler().assemble(timeMs: 1500, state: .waiting)
                point.segmentID = firstID
                cornerID = try store.createCorner(sample: point, note: "Preserved", for: track).id
                try store.append([point], to: track)
                let nodePath = try photos.storeJPEG(jpeg, trackID: track.id, timeMs: 1600)
                let legacyPath = try photos.storeJPEG(jpeg, trackID: track.id, timeMs: 1700)
                paths = [nodePath, legacyPath]
                let metadata = TrackCaptureMetadata(latitude: nil, longitude: nil, altitude: 12, headingDeg: 90)
                _ = try store.createNode(id: nodeID,
                                         tag: TrackTagDraft(timeMs: 1600, tagType: .door, note: "Node", metadata: metadata, createdAt: 1600, floor: "B1"),
                                         photo: TrackPhotoDraft(timeMs: 1600, filePath: nodePath, note: "Node", metadata: metadata,
                                                                createdAt: 1600, kindRawValue: "node", tagID: nodeID), for: track)
                container.mainContext.insert(TrackTag(id: legacyTagID, track: track, timeMs: 1700, tagType: .stairs, createdAt: 1700))
                container.mainContext.insert(TrackPhoto(track: track, timeMs: 1700, filePath: legacyPath, createdAt: 1700))
                try container.mainContext.save()
                for path in paths { try photos.confirmReferenced(relativePath: path) }
                let sample = RawIMUSample(kind: .accelerometer, sensorTimeSeconds: 101, timeMs: 2000, receivedAtMs: 2000,
                                          segmentID: try #require(firstID), x: 0, y: 0, z: -1)
                failure.enabled = true
                for _ in 0..<2 {
                    #expect(throws: Stage4Failure.save) { try store.saveIMU(id: batchID, samples: [sample], status: .init(), for: track) }
                    #expect(track.imuBatches.isEmpty && !container.mainContext.hasChanges)
                    #expect(track.tags.count == 2 && track.photos.count == 2 && track.points.count == 1 && track.corners.count == 1)
                }
                failure.enabled = false
                try store.saveIMU(id: batchID, samples: [sample], status: .init(accelerometer: .stopped, gyroscope: .unsupported), for: track)
                try store.finalize(track, endedAt: 3000)
            }
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                #expect(track.imuBatches.map(\.id) == [batchID] && track.rawAccelState == "stopped" && track.rawGyroState == "unsupported")
                #expect(try track.imuBatches.first?.decodedSamples().count == 1)
                #expect(track.segments.first?.id == firstID && track.segments.first?.endedAt == 3000)
                #expect(track.corners.map(\.id) == [cornerID] && track.points.map(\.timeMs) == [1500])
                #expect(track.tags.count == 2 && track.photos.count == 2)
                #expect(try NodePhotoAssociation.photo(for: #require(track.tags.first { $0.id == nodeID })).filePath == paths[0])
                #expect(track.tags.first { $0.id == legacyTagID }?.recordKindRawValue == "legacy")
                for path in paths { #expect(SHA256.hash(data: try photos.read(relativePath: path)) == SHA256.hash(data: jpeg)) }
            }
        }
    }

    @Test("Failed opt-in Track creation does not leave intent metadata or first segment")
    func atomicStart() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let store = SwiftDataRecordingStore(context: container.mainContext) { _ in throw Stage4Failure.save }
        #expect(throws: Stage4Failure.save) {
            try store.createSegmentedTrack(name: "Synthetic", startedAt: 1000, environment: .unknown, collectRawIMU: true)
        }
        #expect(try container.mainContext.fetch(FetchDescriptor<Track>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<TrackSegment>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<TrackIMUBatch>()).isEmpty)
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage4Migration-\(UUID())")
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

private enum Stage3ReleasedPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoomMarkerSchemaV1.self, RoomMarkerSchemaV2.self, RoomMarkerSchemaV3.self, RoomMarkerSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RoomMarkerSchemaV1.self, toVersion: RoomMarkerSchemaV2.self),
            .lightweight(fromVersion: RoomMarkerSchemaV2.self, toVersion: RoomMarkerSchemaV3.self),
            .lightweight(fromVersion: RoomMarkerSchemaV3.self, toVersion: RoomMarkerSchemaV4.self),
        ]
    }
}
