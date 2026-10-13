import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Offline batch 3 lossless catalog export and disk roundtrip", .serialized)
@MainActor
struct OfflineBatch3ExportTests {
    @Test("ZIP includes catalog, cross-building room links and original node/scenery/legacy photos")
    func zip() async throws {
        let f = try await Stage5Fixture(); defer { f.dispose() }
        let data = Phase2DataStore(context: f.base.context)
        let nodes = f.base.track.tags.filter(\.isNode).sorted { $0.timeMs < $1.timeMs }
        let ra = try data.createRoom(name: "Synthetic classroom A", note: "Keep", area: f.a, code: "X1", floor: "B1")
        let rb = try data.createRoom(name: "Synthetic classroom B", note: "Keep", area: f.b, code: "X1", floor: "2/F")
        nodes[0].tagType = .door; nodes[1].tagType = .classroom
        try f.base.context.save()
        try data.updateTagLocationAndRoom(nodes[0], area: f.a, floor: "B1", roomSelection: .init(roomID: ra.id, doorRole: "后门"))
        try data.updateTagLocationAndRoom(nodes[1], area: f.b, floor: "2/F", roomSelection: .init(roomID: rb.id))
        let original = try f.originalPhotos()
        let payloads = Dictionary(uniqueKeysWithValues: f.base.track.imuBatches.map { ($0.id, $0.payload) })
        let snapshot = try f.snapshot(area: f.a)
        #expect(Set(snapshot.manifest.rooms?.map(\.id) ?? []) == [f.key(ra.id), f.key(rb.id)])
        #expect(snapshot.tracks[0].tags.filter { $0.roomBinding != nil }.count == 2)
        #expect(snapshot.tracks[0].tags[0].roomBinding?.doorRole == "后门")
        let archive = try f.archive.createArchive(from: f.staging.stage(snapshot), areaName: "Synthetic", exportedAt: 70000)
        let entries = try Stage5ZIP.read(archive.archiveURL)
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: #require(entries["manifest.json"]))
        let track = try JSONDecoder().decode(ExportV3Track.self, from: #require(entries[snapshot.tracks[0].file]))
        #expect(manifest == snapshot.manifest && track == snapshot.tracks[0])
        #expect(track.counts == .init(pointCount: 2, tagCount: 3, nodeCount: 2, photoCount: 4, segmentCount: 2, cornerCount: 1, imuSampleCount: 4))
        for (path, bytes) in original {
            let source = try f.base.photos.read(relativePath: path)
            #expect(entries[path] == bytes && SHA256.hash(data: source) == SHA256.hash(data: bytes))
        }
        #expect(f.base.track.imuBatches.allSatisfy { payloads[$0.id] == $0.payload })
        #expect(!f.base.context.hasChanges)
    }

    @Test("Catalog-only v3 export works without Tracks and preserves category, code and floor")
    func emptyCatalog() throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let store = CatalogImportStore(context: f.context)
        try store.apply(store.preview(rows: [.init(building: "AC2", code: "1503", name: "Synthetic", floor: "1F")]))
        let areas = try f.context.fetch(FetchDescriptor<Area>())
        let snapshot = try ExportV3SnapshotBuilder(photoStorage: f.photos).build(tracks: [], areas: areas, exportedAt: 10000)
        #expect(snapshot.tracks.isEmpty && snapshot.manifest.trackCount == 0)
        #expect(snapshot.manifest.areas.first?.category == "城市大学")
        #expect(snapshot.manifest.rooms?.first?.code == "1503" && snapshot.manifest.rooms?.first?.floor == "1/F")
        #expect(snapshot.manifest.rooms?.first?.latitude == nil)
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: f.photos).build(area: #require(areas.first), exportedAt: 10000, allTracks: [])
        }
    }

    @Test("V3 rejects corrupt binding snapshots instead of dropping them", arguments: ["missingName", "orphan", "legacy", "type", "door"])
    func corruptBinding(_ kind: String) async throws {
        let f = try await Stage5Fixture(); defer { f.dispose() }
        let node = try #require(f.base.track.tags.first { $0.isNode })
        node.tagType = .door
        node.roomID = UUID(); node.roomNameSnapshot = "Synthetic"; node.roomCodeSnapshot = "X"; node.roomDoorRole = "前门"
        switch kind {
        case "missingName": node.roomNameSnapshot = nil
        case "orphan": node.roomID = nil
        case "legacy": node.recordKindRawValue = "legacy"
        case "type": node.tagType = .mainGate
        default: node.roomDoorRole = "窗户"
        }
        try f.base.context.save()
        #expect(throws: (any Error).self) { try f.snapshot() }
    }

    @Test("Unassigned room-only export retains catalog even with no Areas or Tracks", arguments: ["all", "unassigned"])
    func unassignedCatalogOnly(_ kind: String) throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let room = try Phase2DataStore(context: f.context).createRoom(name: "Synthetic unassigned", note: "", area: nil, code: "U1")
        let snapshot = try ExportV3SnapshotBuilder(photoStorage: f.photos).build(kind: kind, tracks: [], areas: [], rooms: [room], exportedAt: 1)
        #expect(snapshot.tracks.isEmpty && snapshot.manifest.areas.isEmpty)
        #expect(snapshot.manifest.rooms?.first?.id == room.id.uuidString.lowercased())
        #expect(snapshot.manifest.rooms?.first?.areaId == nil)
    }

    @Test("Old v3 fixtures without optional catalog and binding fields still decode")
    func oldV3() throws {
        let m = try JSONDecoder().decode(ExportV3Manifest.self, from: TestFixtures.data(named: "stage5_legacy_manifest_v3"))
        let t = try JSONDecoder().decode(ExportV3Track.self, from: TestFixtures.data(named: "stage5_legacy_track_v3"))
        #expect(m.rooms == nil && m.areas.allSatisfy { $0.category == nil && $0.catalogKey == nil })
        #expect(t.tags.allSatisfy { $0.roomBinding == nil })
    }

    @Test("V7 disk reopen preserves imported IDs, explicit binding, photo bytes and idempotency")
    func diskRoundtrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Batch3Disk-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("RoomMarker.store")
        let f = try Stage4Fixture(); defer { f.dispose() }
        let photos = try LocalPhotoFileStore(rootURL: root)
        var areaID = UUID(), roomID = UUID(), tagID = UUID(), photoPath = ""
        let row = ClassroomImportRow(building: "AC2", code: "1503", name: "Synthetic room", floor: "1F")
        try autoreleasepool {
            let container = try RoomMarkerModelContainer.make(storeURL: url)
            let c = container.mainContext
            let catalog = CatalogImportStore(context: c)
            try catalog.apply(catalog.preview(rows: [row]))
            let room = try #require(c.fetch(FetchDescriptor<Room>()).first)
            let area = try #require(room.area)
            roomID = room.id; areaID = area.id
            let store = SwiftDataRecordingStore(context: c)
            let track = try store.createTrack(name: "Synthetic room disk", area: nil, startedAt: 1000)
            photoPath = try photos.storeJPEG(f.jpeg, trackID: track.id, timeMs: 2000)
            let metadata = TrackCaptureMetadata(latitude: nil, longitude: nil, altitude: 12, headingDeg: 90,
                                                 accuracy: 3.25, pressureHpa: 1007.75)
            let node = try store.createNode(id: tagID,
                tag: .init(timeMs: 2000, tagType: .door, note: "Synthetic", metadata: metadata, createdAt: 2100,
                           areaID: areaID, areaStateRawValue: "assigned", floor: "1/F",
                           roomSelection: .init(roomID: roomID, doorRole: "后门")),
                photo: .init(timeMs: 2000, filePath: photoPath, note: "Synthetic", metadata: metadata,
                             createdAt: 2100, kindRawValue: "node", tagID: tagID), for: track)
            tagID = node.id
            try photos.confirmReferenced(relativePath: photoPath)
            try store.finalize(track, endedAt: 3000)
        }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try RoomMarkerModelContainer.make(storeURL: url)
                let c = container.mainContext
                let room = try #require(c.fetch(FetchDescriptor<Room>()).first)
                let track = try #require(c.fetch(FetchDescriptor<Track>()).first)
                let node = try #require(track.tags.first)
                #expect(room.id == roomID && room.area?.id == areaID && room.code == "1503" && room.floor == "1/F")
                #expect(node.id == tagID && node.roomID == roomID && node.roomDoorRole == "后门")
                #expect(node.roomNameSnapshot == "Synthetic room" && node.roomCodeSnapshot == "1503")
                #expect(node.accuracy == 3.25 && node.pressureHpa == 1007.75)
                #expect(try NodePhotoAssociation.photo(for: node).filePath == photoPath)
                #expect(SHA256.hash(data: try photos.read(relativePath: photoPath)) == SHA256.hash(data: f.jpeg))
                let again = try CatalogImportStore(context: c).preview(rows: [row])
                #expect(again.newRooms.isEmpty && again.newAreas.isEmpty && again.skipped.count == 1 && again.conflicts.isEmpty)
                let exported = try ExportV3SnapshotBuilder(photoStorage: photos).build(tracks: [track], exportedAt: 4000)
                #expect(exported.tracks.first?.tags.first?.roomBinding?.roomId == roomID.uuidString.lowercased())
                #expect(!c.hasChanges)
            }
        }
    }
}
