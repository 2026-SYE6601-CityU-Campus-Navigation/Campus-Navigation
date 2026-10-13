import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 2 disk persistence", .serialized)
@MainActor
struct Stage2MigrationTests {
    @Test("Actual Stage 1 V2 store migrates without guessing tag-photo pairs")
    func v2Migration() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let trackID = UUID(), tagID = UUID(), photoID = UUID(), areaID = UUID()
            let photoPath = "photos/\(trackID.uuidString.lowercased())/old.jpg"
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let oldPath = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 2000)
            try FileManager.default.moveItem(at: root.appendingPathComponent(oldPath),
                                            to: root.appendingPathComponent(photoPath))
            try photos.confirmReferenced(relativePath: oldPath)
            try autoreleasepool {
                let schema = Schema(versionedSchema: RoomMarkerSchemaV2.self)
                let container = try ModelContainer(
                    for: schema, migrationPlan: Stage1ReleasedPlan.self,
                    configurations: ModelConfiguration("RoomMarker", schema: schema, url: url)
                )
                let context = container.mainContext
                let area = RoomMarkerSchemaV2.Area(id: areaID, name: "Synthetic A", createdAt: 1)
                let track = RoomMarkerSchemaV2.Track(
                    id: trackID, name: "Synthetic Stage 1", startedAt: 1000, endedAt: 3000,
                    isGlobalRecording: true, legacyAreaName: "History"
                )
                context.insert(area)
                context.insert(track)
                context.insert(RoomMarkerSchemaV2.TrackPoint(track: track, timeMs: 1500, headingDeg: 42))
                context.insert(RoomMarkerSchemaV2.TrackTag(
                    id: tagID, track: track, timeMs: 2000, tagType: .door, note: "same",
                    latitude: 0, headingDeg: 90, createdAt: 2100, areaID: areaID,
                    areaStateRawValue: "assigned", floor: "B1"
                ))
                context.insert(RoomMarkerSchemaV2.TrackPhoto(
                    id: photoID, track: track, timeMs: 2000, filePath: photoPath, note: "same",
                    latitude: 0, headingDeg: 90, createdAt: 2100
                ))
                try context.save()
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try RoomMarkerModelContainer.make(storeURL: url)
                    let track = try #require(container.mainContext.fetch(FetchDescriptor<Track>()).first)
                    let tag = try #require(track.tags.first)
                    let photo = try #require(track.photos.first)
                    #expect(tag.accuracy == nil && tag.pressureHpa == nil)
                    #expect(photo.accuracy == nil && photo.pressureHpa == nil)
                    #expect(track.id == trackID && track.isGlobalRecording && track.area == nil)
                    #expect(track.legacyAreaName == "History" && track.points.first?.headingDeg == 42)
                    #expect(tag.id == tagID && tag.recordKindRawValue == "legacy")
                    #expect(tag.areaID == areaID && tag.areaStateRawValue == "assigned" && tag.floor == "B1")
                    #expect(tag.note == "same" && tag.timeMs == 2000 && tag.latitude == 0 && tag.headingDeg == 90)
                    #expect(photo.id == photoID && photo.kindRawValue == "legacyUnlinked" && photo.tagID == nil)
                    #expect(photo.filePath == photoPath && photo.note == "same" && photo.timeMs == 2000)
                    #expect(try photos.read(relativePath: photoPath).count == jpeg.count)
                    #expect(SHA256.hash(data: try photos.read(relativePath: photoPath)) == SHA256.hash(data: jpeg))
                }
            }
        }
    }

    @Test("Node IDs and one-to-one linkage survive disk reopen; pending intent protects committed JPEG")
    func nodeReopen() throws {
        try withRoot { root in
            let url = root.appendingPathComponent("RoomMarker.store")
            let nodeID = UUID(), trackID = UUID()
            let photos = try LocalPhotoFileStore(rootURL: root)
            let jpeg = try makeJPEG()
            let path = try photos.storeJPEG(jpeg, trackID: trackID, timeMs: 2000)
            let metadata = TrackCaptureMetadata(latitude: nil, longitude: nil, altitude: nil, headingDeg: 42)
            var photoID: UUID?
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let track = Track(id: trackID, name: "Synthetic Node", startedAt: 1000, isGlobalRecording: true)
                container.mainContext.insert(track)
                try container.mainContext.save()
                let node = try SwiftDataRecordingStore(context: container.mainContext).createNode(
                    id: nodeID,
                    tag: TrackTagDraft(timeMs: 2000, tagType: .canteen, note: "node", metadata: metadata,
                                       createdAt: 2200, areaStateRawValue: "unassigned"),
                    photo: TrackPhotoDraft(timeMs: 2000, filePath: path, note: "node", metadata: metadata,
                                           createdAt: 2200, kindRawValue: "node", tagID: nodeID),
                    for: track
                )
                photoID = try NodePhotoAssociation.photo(for: node).id
            }
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let context = container.mainContext
                let node = try #require(context.fetch(FetchDescriptor<TrackTag>()).first)
                let photo = try NodePhotoAssociation.photo(for: node)
                #expect(node.id == nodeID && node.tagType == .canteen)
                #expect(photo.id == photoID && photo.track?.id == trackID)
                #expect(photo.headingDeg == 42 && node.timeMs == 2000)
                try photos.retryPendingCleanup(protecting: Set(context.fetch(FetchDescriptor<TrackPhoto>()).map(\.filePath)))
                #expect(try photos.read(relativePath: path) == jpeg)
                #expect(SHA256.hash(data: try photos.read(relativePath: path)) == SHA256.hash(data: jpeg))
            }
        }
    }

    @Test("Pre-deletion intent protects a node after database operation never committed")
    func interruptedDeletion() throws {
        try withRoot { root in
            let store = try LocalPhotoFileStore(rootURL: root)
            let bytes = try makeJPEG()
            let path = try store.storeJPEG(bytes, trackID: UUID(), timeMs: 1)
            try store.confirmReferenced(relativePath: path)
            try store.prepareDeletion(relativePath: path)
            let reopened = try LocalPhotoFileStore(rootURL: root)
            try reopened.retryPendingCleanup(protecting: [path])
            #expect(try reopened.read(relativePath: path) == bytes)
        }
    }

    private func makeJPEG() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage2Migration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}

private enum Stage1ReleasedPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RoomMarkerSchemaV1.self, RoomMarkerSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: RoomMarkerSchemaV1.self, toVersion: RoomMarkerSchemaV2.self)]
    }
}
