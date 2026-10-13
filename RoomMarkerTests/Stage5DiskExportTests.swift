import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 5 disk source preservation", .serialized)
@MainActor
struct Stage5DiskExportTests {
    @Test("Frozen original V1 disk upgrade exports historical Track and JPEG losslessly and reopens unchanged")
    func originalDisk() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let areaID = UUID(), trackID = UUID(), pointID = UUID(), tagID = UUID(), photoID = UUID()
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let path = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 3000)
            try photos.confirmReferenced(relativePath: path)
            try autoreleasepool {
                let schema = Schema(versionedSchema: RoomMarkerSchemaV1.self)
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration("RoomMarker", schema: schema, url: url))
                let c = container.mainContext
                let area = RoomMarkerSchemaV1.Area(id: areaID, name: "Synthetic historical", note: "Retained", createdAt: 1)
                let track = RoomMarkerSchemaV1.Track(id: trackID, name: "Synthetic V1", area: area, startedAt: 1000, endedAt: 5000)
                c.insert(area)
                c.insert(track)
                c.insert(RoomMarkerSchemaV1.TrackPoint(id: pointID, track: track, timeMs: 2000, latitude: 0, longitude: 0,
                                                       altitude: 12, accuracy: 3, pressureHpa: 1008,
                                                       magneticX: 1, magneticY: 2, magneticZ: 3, headingDeg: 90))
                c.insert(RoomMarkerSchemaV1.TrackTag(id: tagID, track: track, timeMs: 3000, tagType: .door, note: "Synthetic independent", createdAt: 3100))
                c.insert(RoomMarkerSchemaV1.TrackPhoto(id: photoID, track: track, timeMs: 3000, filePath: path, note: "Synthetic independent", createdAt: 3100))
                try c.save()
            }
            var frozenJSON: Data?
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let c = container.mainContext
                    let area = try #require(c.fetch(FetchDescriptor<Area>()).first)
                    let track = try #require(c.fetch(FetchDescriptor<Track>()).first)
                    let snapshot = try ExportV3SnapshotBuilder(photoStorage: photos).build(area: area, exportedAt: 6000)
                    let dto = try #require(snapshot.tracks.first)
                    #expect(dto.id == trackID.uuidString.lowercased() && dto.points.first?.id == pointID.uuidString.lowercased())
                    #expect(dto.tags.first?.id == tagID.uuidString.lowercased() && dto.photos.first?.id == photoID.uuidString.lowercased())
                    #expect(dto.legacyAreaId == areaID.uuidString.lowercased() && !dto.isGlobalRecording)
                    #expect(dto.tags.first?.areaState == "unknown" && dto.tags.first?.photoId == nil && dto.photos.first?.tagId == nil)
                    #expect(dto.segments.isEmpty && dto.corners.isEmpty && dto.imu.batches.isEmpty && !dto.imu.requested)
                    let bytes = try ExportJSONEncoder().encode(dto)
                    if let frozenJSON { #expect(bytes == frozenJSON) } else { frozenJSON = bytes }
                    try archiveAndVerify(snapshot, root: root)
                    #expect(track.endedAt == 5000 && track.points.first?.pressureHpa == 1008 && track.points.first?.headingDeg == 90)
                    #expect(track.tags.first?.recordKindRawValue == "legacy" && track.photos.first?.kindRawValue == "legacyUnlinked")
                    #expect(SHA256.hash(data: try photos.read(relativePath: path)) == SHA256.hash(data: jpeg))
                    #expect(!c.hasChanges)
                }
            }
        }
    }

    @Test("V5 disk rich Track exports after reopen and preserves IMU payload and source relationships after cleanup")
    func richDisk() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG(), nodeID = UUID(), batchID = UUID()
            var nodePath = "", segmentID: UUID?, originalPayload: Data?
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let store = SwiftDataRecordingStore(context: container.mainContext)
                let area = Area(name: "Synthetic", createdAt: 1)
                container.mainContext.insert(area)
                try container.mainContext.save()
                let track = try store.createSegmentedTrack(name: "Synthetic rich disk", startedAt: 1000, environment: .indoor, collectRawIMU: true)
                segmentID = try TrackSegmentRules.current(in: track).id
                var point = SampleAssembler().assemble(timeMs: 1500, state: .waiting)
                point.segmentID = segmentID
                _ = try store.createCorner(sample: point, note: "Synthetic", for: track)
                try store.append([point], to: track)
                nodePath = try photos.storeJPEG(jpeg, trackID: track.id, timeMs: 1600)
                let metadata = TrackCaptureMetadata(latitude: 0, longitude: 0, altitude: 12, headingDeg: 90)
                _ = try store.createNode(id: nodeID,
                    tag: .init(timeMs: 1600, tagType: .door, note: "Synthetic", metadata: metadata, createdAt: 1700,
                               areaID: area.id, areaStateRawValue: "assigned", floor: "B1"),
                    photo: .init(timeMs: 1600, filePath: nodePath, note: "Synthetic", metadata: metadata, createdAt: 1700,
                                 kindRawValue: "node", tagID: nodeID), for: track)
                try photos.confirmReferenced(relativePath: nodePath)
                let sample = RawIMUSample(kind: .accelerometer, sensorTimeSeconds: 101, timeMs: 2000, receivedAtMs: 2100,
                                          segmentID: try #require(segmentID), x: 0, y: 0, z: -1)
                try store.saveIMU(id: batchID, samples: [sample], status: .init(accelerometer: .stopped, gyroscope: .unsupported), for: track)
                originalPayload = track.imuBatches.first?.payload
                _ = try store.switchSegment(for: track, to: .outdoor, at: 3000, pendingPoints: [])
                try store.finalize(track, endedAt: 4000)
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let c = container.mainContext
                    let track = try #require(c.fetch(FetchDescriptor<Track>()).first)
                    let snapshot = try ExportV3SnapshotBuilder(photoStorage: photos).build(tracks: [track], exportedAt: 5000)
                    try archiveAndVerify(snapshot, root: root)
                    let dto = try #require(snapshot.tracks.first)
                    #expect(dto.counts == .init(pointCount: 1, tagCount: 1, nodeCount: 1, photoCount: 1, segmentCount: 2, cornerCount: 1, imuSampleCount: 1))
                    #expect(dto.tags.first?.photoId == dto.photos.first?.id && dto.photos.first?.tagId == nodeID.uuidString.lowercased())
                    #expect(dto.imu.gyroscopeState == "unsupported" && dto.imu.gyroscopeCount == 0)
                    #expect(track.imuBatches.first?.id == batchID && track.imuBatches.first?.payload == originalPayload)
                    #expect(track.segments.first { $0.id == segmentID }?.endedAt == 3000)
                    #expect(SHA256.hash(data: try photos.read(relativePath: nodePath)) == SHA256.hash(data: jpeg))
                    #expect(!c.hasChanges)
                }
            }
        }
    }

    private func archiveAndVerify(_ snapshot: ExportV3Snapshot, root: URL) throws {
        let staging = ExportStagingService(baseDirectory: root.appendingPathComponent("export/staging"))
        let service = StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("export/archives"))
        let staged = try staging.stage(snapshot)
        let archive = try service.createArchive(from: staged, areaName: "Synthetic", exportedAt: snapshot.manifest.exportedAt, archiveID: UUID())
        let contents = try Stage5ZIP.read(archive.archiveURL)
        #expect(try JSONDecoder().decode(ExportV3Manifest.self, from: #require(contents["manifest.json"])) == snapshot.manifest)
        for track in snapshot.tracks {
            #expect(try JSONDecoder().decode(ExportV3Track.self, from: #require(contents[track.file])) == track)
        }
        for photo in snapshot.photos { #expect(contents[photo.path] == photo.data) }
        try staging.cleanUp(staged)
        try service.removeArchive(at: archive.archiveURL)
    }
    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage5Disk-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func makeJPEG() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2), format: format).image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }
}
