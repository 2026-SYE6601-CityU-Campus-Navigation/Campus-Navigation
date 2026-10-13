import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 3 disk migrations", .serialized)
@MainActor
struct Stage3MigrationTests {
    @Test("Stage 2 V3 upgrade preserves all seven model kinds, node linkage and JPEG hashes")
    func v3Upgrade() throws {
        try withRoot { (root: URL) throws in
            let url = root.appendingPathComponent("RoomMarker.store")
            let areaID = UUID(), roomID = UUID(), markerID = UUID(), trackID = UUID(), interruptedID = UUID()
            let pointID = UUID(), nodeID = UUID(), legacyTagID = UUID(), photoID = UUID(), legacyPhotoID = UUID()
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let nodePath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 3000)
            let legacyPath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 4000)
            try photos.confirmReferenced(relativePath: nodePath)
            try photos.confirmReferenced(relativePath: legacyPath)
            try autoreleasepool {
                let schema = Schema(versionedSchema: RoomMarkerSchemaV3.self)
                let container = try ModelContainer(
                    for: schema, migrationPlan: Stage2ReleasedPlan.self,
                    configurations: ModelConfiguration("RoomMarker", schema: schema, url: url)
                )
                let context = container.mainContext
                let area = RoomMarkerSchemaV3.Area(id: areaID, name: "Synthetic A", note: "area", createdAt: 1)
                let room = RoomMarkerSchemaV3.Room(
                    id: roomID, name: "Synthetic Room", note: "room", area: area,
                    latitude: 0, longitude: 0, altitude: 12, pressureHpa: 1008, createdAt: 2
                )
                let marker = RoomMarkerSchemaV3.Marker(
                    id: markerID, room: room, name: "Synthetic Door", markerType: .frontDoor,
                    latitude: 0, longitude: 0, altitude: 12, accuracy: 3, pressureHpa: 1008,
                    magneticX: 1, magneticY: 2, magneticZ: 3, createdAt: 3
                )
                let track = RoomMarkerSchemaV3.Track(
                    id: trackID, name: "Synthetic V3", startedAt: 1000, endedAt: 5000,
                    isGlobalRecording: true, legacyAreaName: "Preserved history"
                )
                let interrupted = RoomMarkerSchemaV3.Track(
                    id: interruptedID, name: "Interrupted V3", area: area, startedAt: 6000
                )
                context.insert(area)
                context.insert(room)
                context.insert(marker)
                context.insert(track)
                context.insert(interrupted)
                context.insert(RoomMarkerSchemaV3.TrackPoint(
                    id: pointID, track: track, timeMs: 2000, latitude: 0, longitude: 0,
                    altitude: 12, accuracy: 3, pressureHpa: 1008,
                    magneticX: 1, magneticY: 2, magneticZ: 3, headingDeg: 90
                ))
                context.insert(RoomMarkerSchemaV3.TrackTag(
                    id: nodeID, track: track, timeMs: 3000, tagType: .mainGate, note: "node",
                    headingDeg: 90, createdAt: 3500, areaID: areaID,
                    areaStateRawValue: "assigned", floor: "B1", recordKindRawValue: "node"
                ))
                context.insert(RoomMarkerSchemaV3.TrackTag(
                    id: legacyTagID, track: track, timeMs: 4000, tagType: .door, note: "same", createdAt: 4500
                ))
                context.insert(RoomMarkerSchemaV3.TrackPhoto(
                    id: photoID, track: track, timeMs: 3000, filePath: nodePath, note: "node",
                    headingDeg: 90, createdAt: 3500, kindRawValue: "node", tagID: nodeID
                ))
                context.insert(RoomMarkerSchemaV3.TrackPhoto(
                    id: legacyPhotoID, track: track, timeMs: 4000, filePath: legacyPath, note: "same", createdAt: 4500
                ))
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
                    let point = try #require(track.points.first)
                    let node = try #require(track.tags.first { $0.id == nodeID })
                    let photo = try NodePhotoAssociation.photo(for: node)
                    let legacyTag = try #require(track.tags.first { $0.id == legacyTagID })
                    let legacyPhoto = try #require(track.photos.first { $0.id == legacyPhotoID })
                    #expect(track.tags.allSatisfy { $0.accuracy == nil && $0.pressureHpa == nil })
                    #expect(track.photos.allSatisfy { $0.accuracy == nil && $0.pressureHpa == nil })
                    #expect(area.id == areaID && area.name == "Synthetic A" && area.note == "area")
                    #expect(room.id == roomID && room.area?.id == areaID && room.latitude == 0 && room.pressureHpa == 1008)
                    #expect(marker.id == markerID && marker.room?.id == roomID && marker.magneticZ == 3)
                    #expect(track.name == "Synthetic V3" && track.startedAt == 1000 && track.endedAt == 5000)
                    #expect(track.isGlobalRecording && track.legacyAreaName == "Preserved history")
                    #expect(!track.isSegmentedRecording && track.segments.isEmpty && track.corners.isEmpty)
                    #expect(interrupted.endedAt == nil && interrupted.area?.id == areaID && !interrupted.isSegmentedRecording)
                    #expect(point.id == pointID && point.timeMs == 2000 && point.segmentID == nil)
                    #expect(point.latitude == 0 && point.longitude == 0 && point.headingDeg == 90 && point.pressureHpa == 1008)
                    #expect(point.wifiAvailability == .unsupported && point.wifiCount == nil && point.wifiTop == nil)
                    #expect(node.areaID == areaID && node.floor == "B1" && node.tagType == .mainGate)
                    #expect(node.isNode && node.timeMs == 3000 && node.createdAt == 3500 && node.headingDeg == 90)
                    #expect(photo.id == photoID && photo.tagID == nodeID && photo.filePath == nodePath && photo.headingDeg == 90)
                    #expect(legacyTag.recordKindRawValue == "legacy" && legacyTag.areaID == nil)
                    #expect(legacyPhoto.kindRawValue == "legacyUnlinked" && legacyPhoto.tagID == nil && legacyPhoto.filePath == legacyPath)
                    #expect(try context.fetch(FetchDescriptor<TrackSegment>()).isEmpty)
                    #expect(try context.fetch(FetchDescriptor<TrackCorner>()).isEmpty)
                    for path in [nodePath, legacyPath] {
                        let bytes = try photos.read(relativePath: path)
                        #expect(bytes.count == jpeg.count && SHA256.hash(data: bytes) == SHA256.hash(data: jpeg))
                        #expect(UIImage(data: bytes) != nil)
                    }
                }
            }
        }
    }

    @Test("Current disk store preserves segment IDs, bounds, point membership and corner snapshots")
    func currentRoundtrip() throws {
        try withRoot { (root: URL) throws in
            let url = root.appendingPathComponent("RoomMarker.store")
            var trackID: UUID?, firstID: UUID?, secondID: UUID?, cornerID: UUID?
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let store = SwiftDataRecordingStore(context: container.mainContext)
                let track = try store.createSegmentedTrack(name: "Synthetic Roundtrip", startedAt: 1000, environment: .indoor)
                trackID = track.id
                firstID = try TrackSegmentRules.current(in: track).id
                var sample = SampleAssembler().assemble(timeMs: 2000, state: .waiting)
                sample.segmentID = firstID
                let corner = try store.createCorner(sample: sample, note: "Synthetic turn", for: track)
                cornerID = corner.id
                let second = try store.switchSegment(for: track, to: .outdoor, at: 3000, pendingPoints: [sample])
                secondID = second.id
                sample = SampleAssembler().assemble(timeMs: 4000, state: .waiting)
                sample.segmentID = second.id
                try store.append([sample], to: track)
                try store.finalize(track, endedAt: 5000)
            }
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                let segments = TrackSegmentRules.ordered(in: track)
                #expect(track.id == trackID && track.isSegmentedRecording && track.endedAt == 5000)
                #expect(segments.map(\.id) == [firstID, secondID])
                #expect(segments.map(\.startedAt) == [1000, 3000] && segments.map(\.endedAt) == [3000, 5000])
                #expect(segments.map(\.environmentRawValue) == ["indoor", "outdoor"])
                #expect(track.points.first { $0.timeMs == 2000 }?.segmentID == firstID)
                #expect(track.points.first { $0.timeMs == 4000 }?.segmentID == secondID)
                let corner = try #require(track.corners.first)
                #expect(corner.id == cornerID && corner.segmentID == firstID && corner.timeMs == 2000)
                #expect(corner.note == "Synthetic turn" && corner.latitude == nil && corner.headingDeg == nil)
                #expect(track.tags.isEmpty && track.photos.isEmpty)
            }
        }
    }

    @Test("Reopening interrupted recording keeps last segment open and never adds catch-up evidence")
    func interruptedReopen() throws {
        try withRoot { (root: URL) throws in
            let url = root.appendingPathComponent("RoomMarker.store")
            var segmentID: UUID?
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let store = SwiftDataRecordingStore(context: container.mainContext)
                let track = try store.createSegmentedTrack(name: "Interrupted", startedAt: 1000, environment: .unknown)
                segmentID = try TrackSegmentRules.current(in: track).id
                var sample = SampleAssembler().assemble(timeMs: 2000, state: .waiting)
                sample.segmentID = segmentID
                try store.append([sample], to: track)
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                    #expect(track.endedAt == nil && track.segments.count == 1)
                    #expect(track.segments.first?.id == segmentID && track.segments.first?.endedAt == nil)
                    #expect(track.points.map(\.timeMs) == [2000] && track.corners.isEmpty)
                }
            }
        }
    }

    @Test("Failed boundary and corner inserts never reappear after retry and disk reopen")
    func rollbackRoundtrip() throws {
        try withRoot { (root: URL) throws in
            let url = root.appendingPathComponent("RoomMarker.store")
            var pointID: UUID?, cornerID: UUID?, firstID: UUID?, secondID: UUID?
            let nodeID = UUID(), legacyTagID = UUID()
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            var originalPaths: [String] = []
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let failure = Stage3MigrationSaveFailure()
                let store = SwiftDataRecordingStore(context: container.mainContext) {
                    if failure.enabled { throw Stage3MigrationFailure.save }
                    try $0.save()
                }
                let track = try store.createSegmentedTrack(name: "Rollback", startedAt: 1000, environment: .unknown)
                firstID = try TrackSegmentRules.current(in: track).id
                var sample = SampleAssembler().assemble(timeMs: 1500, state: .waiting)
                sample.segmentID = firstID
                cornerID = try store.createCorner(sample: sample, note: "Preserved", for: track).id
                sample = SampleAssembler().assemble(timeMs: 2000, state: .waiting)
                sample.segmentID = firstID
                try store.append([sample], to: track)
                pointID = try #require(track.points.first?.id)
                let nodePath = try photos.storeJPEG(jpeg, trackID: track.id, timeMs: 1800)
                let legacyPath = try photos.storeJPEG(jpeg, trackID: track.id, timeMs: 1900)
                originalPaths = [nodePath, legacyPath]
                let metadata = TrackCaptureMetadata(latitude: nil, longitude: nil, altitude: 12, headingDeg: 90)
                _ = try store.createNode(
                    id: nodeID,
                    tag: TrackTagDraft(timeMs: 1800, tagType: .door, note: "Node", metadata: metadata,
                                       createdAt: 1800, floor: "B1"),
                    photo: TrackPhotoDraft(timeMs: 1800, filePath: nodePath, note: "Node", metadata: metadata,
                                           createdAt: 1800, kindRawValue: "node", tagID: nodeID),
                    for: track
                )
                container.mainContext.insert(TrackTag(
                    id: legacyTagID, track: track, timeMs: 1900, tagType: .stairs, createdAt: 1900
                ))
                container.mainContext.insert(TrackPhoto(
                    track: track, timeMs: 1900, filePath: legacyPath, createdAt: 1900
                ))
                try container.mainContext.save()
                try photos.confirmReferenced(relativePath: nodePath)
                try photos.confirmReferenced(relativePath: legacyPath)
                var tail = SampleAssembler().assemble(timeMs: 2500, state: .waiting)
                tail.segmentID = firstID
                failure.enabled = true
                #expect(throws: Stage3MigrationFailure.save) {
                    try store.switchSegment(for: track, to: .outdoor, at: 3000, pendingPoints: [tail])
                }
                #expect(track.segments.count == 1 && track.segments.first?.endedAt == nil)
                #expect(track.points.count == 1 && track.corners.count == 1)
                #expect(!container.mainContext.hasChanges)
                #expect(throws: Stage3MigrationFailure.save) {
                    try store.createCorner(sample: tail, note: "Not committed", for: track)
                }
                #expect(track.segments.count == 1 && track.segments.first?.endedAt == nil)
                #expect(track.points.count == 1 && track.corners.count == 1)
                #expect(!container.mainContext.hasChanges)
                failure.enabled = false
                secondID = try store.switchSegment(for: track, to: .outdoor, at: 3000, pendingPoints: [tail]).id
                try store.finalize(track, endedAt: 4000)
            }
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                #expect(track.points.count == 2 && track.points.map(\.timeMs).sorted() == [2000, 2500])
                #expect(track.points.first { $0.timeMs == 2000 }?.id == pointID)
                #expect(track.points.allSatisfy { $0.segmentID == firstID })
                #expect(TrackSegmentRules.ordered(in: track).map(\.id) == [firstID, secondID])
                #expect(track.corners.count == 1 && track.corners.first?.id == cornerID)
                #expect(track.corners.first?.note == "Preserved" && track.corners.first?.timeMs == 1500)
                #expect(track.tags.count == 2 && track.photos.count == 2)
                let node = try #require(track.tags.first { $0.id == nodeID })
                let photo = try NodePhotoAssociation.photo(for: node)
                #expect(node.floor == "B1" && photo.filePath == originalPaths[0])
                #expect(photo.tagID == nodeID && photo.timeMs == 1800 && photo.headingDeg == 90)
                #expect(track.tags.first { $0.id == legacyTagID }?.recordKindRawValue == "legacy")
                #expect(track.photos.first { $0.filePath == originalPaths[1] }?.tagID == nil)
                for path in originalPaths {
                    let bytes = try photos.read(relativePath: path)
                    #expect(bytes.count == jpeg.count && SHA256.hash(data: bytes) == SHA256.hash(data: jpeg))
                }
                #expect(try container.mainContext.fetch(FetchDescriptor<TrackSegment>()).count == 2)
                #expect(try container.mainContext.fetch(FetchDescriptor<TrackCorner>()).count == 1)
            }
        }
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage3Migration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makeJPEG() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }
}

private enum Stage3MigrationFailure: Error, Equatable { case save }

@MainActor
private final class Stage3MigrationSaveFailure { var enabled = false }

private enum Stage2ReleasedPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoomMarkerSchemaV1.self, RoomMarkerSchemaV2.self, RoomMarkerSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RoomMarkerSchemaV1.self, toVersion: RoomMarkerSchemaV2.self),
            .lightweight(fromVersion: RoomMarkerSchemaV2.self, toVersion: RoomMarkerSchemaV3.self),
        ]
    }
}
