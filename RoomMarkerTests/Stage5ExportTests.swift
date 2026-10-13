import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 5 lossless JSON v3 and ZIP", .serialized)
@MainActor
struct Stage5ExportTests {
    @Test("Area selection exports the entire cross-building Track once, including the other building")
    func crossBuilding() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        for area in [f.a, f.b] {
            let snapshot = try f.snapshot(area: area)
            #expect(snapshot.tracks.map(\.id) == [f.id])
            #expect(snapshot.manifest.areas.map(\.id).sorted() == [f.key(f.a.id), f.key(f.b.id)].sorted())
            let track = try #require(snapshot.tracks.first)
            #expect(track.counts == .init(pointCount: 2, tagCount: 3, nodeCount: 2, photoCount: 4, segmentCount: 2, cornerCount: 1, imuSampleCount: 4))
            #expect(track.tags.filter { $0.recordKind == "node" }.map(\.floor) == ["B1", "2/F"])
            #expect(track.isGlobalRecording && track.legacyAreaId == nil)
        }
    }

    @Test("v3 JSON roundtrip retains stable IDs, all sensor values, timestamps and explicit null semantics")
    func roundtrip() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let source = try f.snapshot()
        let dto = try #require(source.tracks.first)
        let bytes = try ExportJSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(ExportV3Track.self, from: bytes)
        #expect(decoded == dto && decoded.id == f.id)
        #expect(decoded.points.map(\.id) == f.base.track.points.sorted { $0.timeMs < $1.timeMs }.map { f.key($0.id) })
        #expect(decoded.points[0].latitude == 0 && decoded.points[0].longitude == 0)
        #expect(decoded.points[0].pressureHpa == 1008 && decoded.points[0].magneticZ == 3 && decoded.points[0].headingDeg == 90)
        #expect(decoded.points[1].latitude == nil && decoded.points[1].pressureHpa == nil)
        #expect(decoded.corners.first?.note == "Synthetic turn" && decoded.corners.first?.altitude == 12)
        #expect(decoded.tags.last?.recordKind == "legacy" && decoded.tags.last?.areaState == "unknown")
        #expect(decoded.photos.last?.kind == "legacyUnlinked" && decoded.photos.last?.tagId == nil)
    }

    @Test("Node-photo references are bidirectional and historical independent records stay independent")
    func associations() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let track = try #require(try f.snapshot().tracks.first)
        for tag in track.tags where tag.recordKind == "node" {
            let photo = try #require(track.photos.first { $0.id == tag.photoId })
            #expect(photo.tagId == tag.id && photo.kind == "node" && photo.timeMs == tag.timeMs)
            #expect(photo.headingDeg == tag.headingDeg && photo.altitude == tag.altitude)
        }
        #expect(track.tags.last?.photoId == nil)
        #expect(track.photos.filter { $0.kind != "node" }.allSatisfy { $0.tagId == nil })
    }

    @Test("All eleven node types export without translating or collapsing categories", arguments: TrackTagType.allCases)
    func nodeTypes(_ type: TrackTagType) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let node = try #require(f.base.track.tags.first { $0.isNode })
        node.tagType = type
        try f.base.context.save()
        #expect(try f.snapshot().tracks.first?.tags.first { $0.id == f.key(node.id) }?.tagType == type.rawValue)
    }

    @Test("Controlled timestamp gaps and original IMU timestamps survive without catch-up or resampling")
    func gapsAndRawIMU() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let track = try #require(try f.snapshot().tracks.first)
        #expect(track.points.map(\.timeMs) == [2000, 61000])
        let samples = track.imu.batches.flatMap(\.samples)
        #expect(samples.map(\.timeMs) == [2000, 2020, 61000, 61020])
        #expect(samples.map(\.sensorTimeSeconds) == [101, 101.02, 160, 160.02])
        #expect(samples.map(\.receivedAtMs) == [2100, 2100, 61500, 61500])
        #expect(samples.map(\.x) == [0, 0.1, 1, 0.4] && samples[0].z == -1)
        #expect(track.imu.accelerometerUnit == "g" && track.imu.gyroscopeUnit == "rad/s")
        #expect(track.imu.accelerometerIncludesGravity && track.imu.backgroundPolicy == "foregroundOnlyNoCatchUp")
        #expect(track.imu.accelerationCount == 2 && track.imu.gyroscopeCount == 2 && track.imu.requestedIntervalSeconds == 0.02)
        #expect(samples[0].segmentId == track.segments[0].id && samples[3].segmentId == track.segments[1].id)
    }

    @Test("Delayed independent channel does not force batch reordering into fake synchronized frames")
    func delayedChannelAcrossBatches() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        for index in 0..<100 { f.emit(.accelerometer, at: 101 + Double(index) * 0.02) }
        f.emit(.gyroscope, at: 100.1)
        f.emit(.accelerometer, at: 104)
        f.clock.wall = 6000
        try await f.coordinator.stop()
        let source = Dictionary(uniqueKeysWithValues: f.track.imuBatches.map { ($0.id.uuidString.lowercased(), $0.payload) })
        let snapshot = try ExportV3SnapshotBuilder(photoStorage: f.photos).build(tracks: [f.track], exportedAt: 7000)
        #expect(snapshot.tracks.first?.imu.sampleCount == 102 && snapshot.tracks.first?.imu.batches.count == 2)
        for batch in try #require(snapshot.tracks.first?.imu.batches) {
            let original = try JSONDecoder().decode([RawIMUSample].self, from: #require(source[batch.id]))
            #expect(batch.samples.map(\.sensorTimeSeconds) == original.map(\.sensorTimeSeconds))
            #expect(batch.samples.map(\.timeMs) == original.map(\.timeMs))
        }
    }

    @Test("Historical single-Area data exports as v3 without fabricated segments, nodes, IMU or location")
    func history() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let old = Track(name: "Synthetic historical", area: f.a, startedAt: 10, endedAt: 900, legacyAreaName: "Original hint")
        f.base.context.insert(old)
        f.base.context.insert(TrackPoint(track: old, timeMs: 20))
        let tag = TrackTag(track: old, timeMs: 30, tagType: .door, createdAt: 31)
        f.base.context.insert(tag)
        try f.base.context.save()
        let snapshot = try f.snapshot(area: f.a)
        let result = try #require(snapshot.tracks.first { $0.id == f.key(old.id) })
        #expect(!result.isGlobalRecording && result.legacyAreaId == f.key(f.a.id) && result.legacyAreaName == "Original hint")
        #expect(result.segments.isEmpty && result.corners.isEmpty && result.points.first?.segmentId == nil)
        #expect(result.tags.first?.recordKind == "legacy" && result.tags.first?.areaState == "unknown" && result.tags.first?.photoId == nil)
        #expect(result.imu.batches.isEmpty && !result.imu.requested && result.imu.accelerometerState == "notRequested")
        #expect(result.points.first?.latitude == nil && snapshot.tracks.count == 2)
        #expect(old.area?.id == f.a.id && tag.areaID == nil && !f.base.context.hasChanges)
    }

    @Test("Existing v1/v2 compatibility fixtures still decode without importing or mutating storage")
    func oldJSON() throws {
        for name in ["harmony_track_v1", "ios_track_v2", "ios_interrupted_track_v2"] {
            let dto = try JSONDecoder().decode(ExportedTrackDTO.self, from: TestFixtures.data(named: name))
            #expect([1, 2].contains(dto.version))
        }
    }

    @Test("All-Tracks export includes tagless and unknown records, unassigned selection does not infer membership")
    func selection() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let tagless = Track(name: "Synthetic tagless", startedAt: 5, endedAt: 6, isGlobalRecording: true)
        let old = Track(name: "Synthetic old unassigned", startedAt: 7, endedAt: 8)
        f.base.context.insert(tagless)
        f.base.context.insert(old)
        try f.base.context.save()
        #expect(try f.snapshot().tracks.count == 3)
        let unassigned = try f.builder.build(kind: "unassigned", tracks: f.tracks(), exportedAt: 70000)
        #expect(unassigned.tracks.map(\.id) == [f.key(old.id)])
        #expect(unassigned.manifest.scope.kind == "unassigned")
        let node = try #require(f.base.track.tags.first { $0.isNode })
        node.areaID = nil
        node.areaStateRawValue = "unassigned"
        try f.base.context.save()
        let withGlobal = try f.builder.build(kind: "unassigned", tracks: f.tracks(), exportedAt: 70000)
        #expect(Set(withGlobal.tracks.map(\.id)) == [f.id, f.key(old.id)])
        #expect(withGlobal.tracks.first { $0.id == f.id }?.counts.photoCount == 4)
    }

    @Test("Interrupted Track keeps nil end and open segment without automatic completion")
    func interrupted() async throws {
        let f = try await Stage5Fixture(complete: false)
        defer { f.dispose() }
        let track = try #require(try f.snapshot().tracks.first)
        #expect(track.endedAt == nil && track.segments.last?.endedAt == nil && track.imu.sampleCount == 4)
        #expect(f.base.track.endedAt == nil && !f.base.context.hasChanges)
    }

    @Test("Snapshot is immutable and repeated unchanged JSON is byte-identical")
    func frozenSnapshot() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let a = try f.snapshot(), b = try f.snapshot()
        #expect(try ExportJSONEncoder().encode(a.manifest) == ExportJSONEncoder().encode(b.manifest))
        #expect(try ExportJSONEncoder().encode(a.tracks) == ExportJSONEncoder().encode(b.tracks))
        f.base.track.name = "Later edit"
        f.base.track.tags.first?.floor = "Changed"
        #expect(a.tracks.first?.name != "Later edit" && a.tracks.first?.tags.first?.floor != "Changed")
        f.base.context.rollback()
    }

    @Test("No fabricated Wi-Fi, internal filesystem paths, staging names or source platform ambiguity")
    func capabilitiesAndPrivacy() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let snapshot = try f.snapshot()
        #expect(snapshot.manifest.version == 3 && snapshot.manifest.sourcePlatform == "ios")
        #expect(snapshot.manifest.capabilities.nearbyWifiFingerprint == .unsupported)
        let bytes = try ExportJSONEncoder().encode(snapshot.tracks)
        let text = String(decoding: bytes, as: UTF8.self)
        for forbidden in ["wifiCount", "wifiTop", "BSSID", "RSSI", "/private/", "/var/", "/Users/", "staging/"] { #expect(!text.contains(forbidden)) }
        #expect(snapshot.tracks.allSatisfy { $0.photos.allSatisfy { ArchivePathValidator.isSafe($0.file) } })
    }

    @Test("Builder rejects active Track before producing an incomplete snapshot")
    func activeGuard() async throws {
        let f = try await Stage5Fixture(complete: false)
        defer { f.dispose() }
        #expect(throws: ExportV3Error.activeTrack) {
            try f.builder.build(tracks: [f.base.track], areas: [f.a, f.b], exportedAt: 70000, activeTrackID: f.base.track.id)
        }
    }

    @Test("Malformed ownership, associations, areas, segments, IMU and sensor values fail without rewriting source", arguments: ["tagKind", "photoKind", "orphan", "area", "areaState", "segment", "environment", "boundary", "pointSegment", "cornerSegment", "imu", "finite", "wifi"])
    func malformed(_ defect: String) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        switch defect {
        case "tagKind": f.base.track.tags[0].recordKindRawValue = "bad"
        case "photoKind": f.base.track.photos[0].kindRawValue = "bad"
        case "orphan": f.base.track.photos[0].tagID = UUID()
        case "area": f.base.track.tags[0].areaID = UUID()
        case "areaState": f.base.track.tags[0].areaStateRawValue = "bad"
        case "segment": f.base.track.segments[0].ordinal = 9
        case "environment": f.base.track.segments[0].environmentRawValue = "bad"
        case "boundary": f.base.track.segments[0].endedAt = 4000
        case "pointSegment": f.base.track.points[0].segmentID = UUID()
        case "cornerSegment": f.base.track.corners[0].segmentID = UUID()
        case "imu": f.base.track.imuBatches[0].sampleCount += 1
        case "finite": f.base.track.points[0].latitude = .infinity
        default: f.base.track.points[0].wifiCount = 1
        }
        try f.base.context.save()
        let photoBytes = try f.originalPhotos()
        #expect(throws: (any Error).self) { try f.snapshot() }
        #expect(try f.originalPhotos() == photoBytes && !f.base.context.hasChanges)
    }

    @Test("Missing and corrupt JPEG abort export; source metadata is not deleted", arguments: [false, true])
    func invalidJPEG(_ corrupt: Bool) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let photo = try #require(f.base.track.photos.first)
        if corrupt {
            try Data("not jpeg".utf8).write(to: f.base.root.appendingPathComponent(photo.filePath))
        } else { try f.base.photos.delete(relativePath: photo.filePath) }
        #expect(throws: (any Error).self) { try f.snapshot() }
        #expect(f.base.track.photos.count == 4 && f.base.track.tags.count == 3)
    }

    @Test("Complete ZIP has valid local/central records, CRCs and exact JSON/JPEG bytes; no source mutation")
    func archiveIntegrity() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let originals = try f.originalPhotos()
        let snapshot = try f.snapshot()
        let staged = try f.staging.stage(snapshot)
        let zip = try f.archive.createArchive(from: staged, areaName: "Synthetic", exportedAt: 70000, archiveID: UUID())
        let entries = try Stage5ZIP.read(zip.archiveURL)
        #expect(entries.count == 6 && Set(entries.keys) == Set(zip.entryPaths))
        #expect(entries.keys.allSatisfy(ArchivePathValidator.isSafe))
        #expect(entries.keys.allSatisfy { !$0.contains(staged.sessionDirectory.lastPathComponent) })
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: #require(entries["manifest.json"]))
        #expect(manifest == snapshot.manifest && manifest.trackCount == 1)
        let track = try JSONDecoder().decode(ExportV3Track.self, from: #require(entries["tracks/\(f.id).json"]))
        #expect(track == snapshot.tracks[0] && manifest.tracks[0].counts == track.counts)
        for photo in track.photos {
            let bytes = try #require(entries[photo.file])
            #expect(bytes == originals[photo.file] && bytes.count == photo.byteCount)
            let original = try #require(UIImage(data: f.base.jpeg))
            let image = try #require(UIImage(data: bytes))
            #expect(f.hash(bytes) == photo.sha256 && image.cgImage?.width == original.cgImage?.width &&
                    image.cgImage?.height == original.cgImage?.height && image.imageOrientation == original.imageOrientation)
        }
        try f.staging.cleanUp(staged)
        #expect(!FileManager.default.fileExists(atPath: staged.sessionDirectory.path))
        #expect(try f.originalPhotos() == originals && !f.base.context.hasChanges)
        #expect(f.base.track.points.count == 2 && f.base.track.imuBatches.count == 1)
    }

    @Test("Manifest-only empty v3 archive is valid")
    func empty() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let empty = Area(name: "Empty", createdAt: 1)
        f.base.context.insert(empty)
        try f.base.context.save()
        let snapshot = try f.snapshot(area: empty)
        let staged = try f.staging.stage(snapshot)
        let zip = try f.archive.createArchive(from: staged, areaName: "Empty", exportedAt: 1, archiveID: UUID())
        #expect(try Stage5ZIP.read(zip.archiveURL).keys.sorted() == ["manifest.json"])
        #expect(snapshot.manifest.trackCount == 0 && snapshot.manifest.areas.map(\.id) == [f.key(empty.id)])
    }

    @Test("Tampered manifest count, IDs or relative photo paths are rejected before staging", arguments: ["count", "id", "traversal", "absolute", "sibling"])
    func tamperedSnapshot(_ defect: String) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let snapshot = try f.snapshot()
        var manifest = snapshot.manifest, tracks = snapshot.tracks
        if defect == "count" {
            manifest = try edit(manifest) { $0["trackCount"] = 9 }
        } else {
            tracks[0] = try edit(tracks[0]) { json in
                if defect == "id" { json["id"] = "../bad"; return }
                var photos = json["photos"] as! [[String: Any]]
                photos[0]["file"] = defect == "traversal" ? "../evil.jpg" : defect == "absolute" ? "/private/evil.jpg" : "photos/\(f.id)-evil/x.jpg"
                json["photos"] = photos
            }
        }
        #expect(throws: (any Error).self) {
            try f.staging.stage(.init(manifest: manifest, tracks: tracks, photos: snapshot.photos))
        }
        #expect(!FileManager.default.fileExists(atPath: f.stageRoot.path))
    }

    @Test("v3 staging write failure removes only its partial session and retains source JPEGs")
    func writeFailure() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let originals = try f.originalPhotos(), id = UUID()
        let service = ExportStagingService(baseDirectory: f.stageRoot, fileSystem: Stage5FailingFS())
        #expect(throws: (any Error).self) { try service.stage(f.snapshot(), sessionID: id) }
        #expect(!FileManager.default.fileExists(atPath: f.stageRoot.appendingPathComponent(f.key(id)).path))
        #expect(try f.originalPhotos() == originals)
    }

    @Test("v3 staging rejects a symlink escape and never touches external sentinel or source")
    func symlinkEscape() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let outside = f.base.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("preserve".utf8).write(to: sentinel)
        let originals = try f.originalPhotos(), id = UUID()
        let service = ExportStagingService(baseDirectory: f.stageRoot,
                                          fileSystem: Stage5SymlinkFS(session: f.key(id), outside: outside))
        #expect(throws: (any Error).self) { try service.stage(f.snapshot(), sessionID: id) }
        #expect(try Data(contentsOf: sentinel) == Data("preserve".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["sentinel"])
        #expect(try f.originalPhotos() == originals)
    }

    @Test("v3 workflow shares one ZIP, cleans staging and only removes archive on dismissal")
    func workflow() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let originals = try f.originalPhotos()
        let coordinator = AreaExportCoordinator(photoStorage: f.base.photos, stagingService: f.staging,
                                                 archiveService: f.archive, nowMilliseconds: { 70000 })
        try coordinator.startV3(area: f.a, allTracks: f.tracks())
        await coordinator.waitForCurrentExport()
        guard case let .readyToShare(result) = coordinator.state else { Issue.record("Expected v3 ZIP"); return }
        #expect(ExportSharePayload(result: result).items == [result.archiveURL])
        let entries = try Stage5ZIP.read(result.archiveURL)
        #expect(entries.count == 7 && entries["index.html"] != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stageRoot.path).isEmpty)
        coordinator.resetAfterSharing()
        #expect(coordinator.state == .idle && !FileManager.default.fileExists(atPath: result.archiveURL.path))
        #expect(try f.originalPhotos() == originals && !f.base.context.hasChanges)
    }

    @Test("All-Tracks workflow checks live recording identity when the snapshot is actually frozen")
    func workflowActiveGuard() async throws {
        let f = try await Stage5Fixture(complete: false)
        defer { f.dispose() }
        let coordinator = AreaExportCoordinator(photoStorage: f.base.photos, stagingService: f.staging,
                                                 archiveService: f.archive, activeTrackID: { f.base.track.id })
        try coordinator.startAllV3(tracks: f.tracks())
        await coordinator.waitForCurrentExport()
        guard case let .failed(error) = coordinator.state else { Issue.record("Expected active guard"); return }
        #expect(error.message == ExportV3Error.activeTrack.localizedDescription)
        #expect(!FileManager.default.fileExists(atPath: f.stageRoot.path))
    }

    @Test("Cancellation leaves no v3 share item, archive or source changes")
    func cancellation() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let originals = try f.originalPhotos()
        let coordinator = AreaExportCoordinator(photoStorage: f.base.photos, stagingService: f.staging, archiveService: f.archive)
        try coordinator.startAllV3(tracks: f.tracks())
        coordinator.cancelAndReset()
        await coordinator.waitForCurrentExport()
        await Task.yield()
        #expect(try coordinator.state == .idle && f.originalPhotos() == originals)
    }

    @Test("A cancelled generation cannot overwrite a subsequent v3 export")
    func cancelThenRestart() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let coordinator = AreaExportCoordinator(photoStorage: f.base.photos, stagingService: f.staging, archiveService: f.archive)
        try coordinator.startV3(area: f.a, allTracks: f.tracks())
        coordinator.cancelAndReset()
        try coordinator.startAllV3(tracks: f.tracks())
        await coordinator.waitForCurrentExport()
        guard case let .readyToShare(result) = coordinator.state else { Issue.record("Stale generation changed state"); return }
        let entries = try Stage5ZIP.read(result.archiveURL)
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: #require(entries["manifest.json"]))
        #expect(manifest.scope.kind == "all" && manifest.trackCount == 1)
    }

    @Test("Frozen synthetic v3 fixtures preserve historical unknown values without migration guesses")
    func goldenLegacyV3() throws {
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: TestFixtures.data(named: "stage5_legacy_manifest_v3"))
        let track = try JSONDecoder().decode(ExportV3Track.self, from: TestFixtures.data(named: "stage5_legacy_track_v3"))
        try ExportV3Validator.validate(.init(manifest: manifest, tracks: [track], photos: []))
        #expect(track.tags.first?.areaState == "unknown" && track.points.first?.segmentId == nil)
        #expect(track.legacyAreaName == "Synthetic historical hint" && track.imu.sampleCount == 0)
    }

    private func edit<T: Codable>(_ value: T, change: (inout [String: Any]) -> Void) throws -> T {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        change(&json)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

@MainActor
final class Stage5Fixture {
    let base: Stage4Fixture
    let a: Area
    let b: Area
    let builder: ExportV3SnapshotBuilder
    var id: String { key(base.track.id) }
    var stageRoot: URL { base.root.appendingPathComponent("export/staging") }
    var staging: ExportStagingService { .init(baseDirectory: stageRoot) }
    var archive: StoredZIPArchiveService { .init(archiveDirectory: base.root.appendingPathComponent("export/archives")) }

    init(complete: Bool = true) async throws {
        base = try Stage4Fixture()
        a = Area(name: "Synthetic Building", note: "A", createdAt: 1)
        b = Area(name: "Synthetic Building", note: "B", createdAt: 2)
        base.context.insert(a)
        base.context.insert(b)
        try base.context.save()
        builder = ExportV3SnapshotBuilder(photoStorage: base.photos)
        let capturedAt = Date()
        base.hub.state = LiveSensorState(permission: .authorizedWhenInUse,
            location: .available(.init(value: .init(latitude: 0, longitude: 0, altitude: 12, horizontalAccuracy: 3), capturedAt: capturedAt)),
            pressureHpa: .available(.init(value: 1008, capturedAt: capturedAt)),
            magneticField: .available(.init(value: .init(x: 1, y: 2, z: 3), capturedAt: capturedAt)),
            headingDeg: .available(.init(value: 90, capturedAt: capturedAt)))
        base.clock.wall = 1500
        _ = try base.coordinator.captureCorner(note: "Synthetic turn")
        base.clock.wall = 1600
        _ = try base.coordinator.saveNode(capture: base.captureForStage5(), type: .door, note: "Synthetic A node", area: a, floor: "B1")
        base.clock.wall = 2100
        base.emit(.accelerometer, at: 101, x: 0, y: 0, z: -1)
        base.emit(.gyroscope, at: 101.02, x: 0.1, y: -0.2, z: 0.3)
        await base.ticker.fire(2000)
        base.clock.wall = 3000
        try base.coordinator.changeEnvironment(to: .outdoor)
        base.clock.wall = 3500
        _ = try base.coordinator.saveNode(capture: base.captureForStage5(), type: .elevator, note: "Synthetic B node", area: b, floor: "2/F")
        base.clock.wall = 3600
        _ = try base.coordinator.handlePhotoCapture(.success(jpegData: base.jpeg, capturedAt: 3600), note: "Synthetic scenery")
        let path = try base.photos.storeJPEG(base.jpeg, trackID: base.track.id, timeMs: 3700)
        base.context.insert(TrackTag(track: base.track, timeMs: 3700, tagType: .stairs, note: "Synthetic legacy", createdAt: 3700))
        base.context.insert(TrackPhoto(track: base.track, timeMs: 3700, filePath: path, note: "Synthetic legacy", createdAt: 3700))
        try base.context.save()
        try base.photos.confirmReferenced(relativePath: path)
        base.hub.state = .waiting
        base.clock.wall = 61500
        base.emit(.accelerometer, at: 160, x: 1, y: 2, z: 3)
        base.emit(.gyroscope, at: 160.02, x: 0.4, y: 0.5, z: 0.6)
        await base.ticker.fire(61000)
        base.clock.wall = 62000
        if complete { try await base.coordinator.stop() } else { try base.imu.stopAndFlush() }
    }
    func tracks() throws -> [Track] { try base.context.fetch(FetchDescriptor<Track>()) }
    func snapshot(area: Area? = nil) throws -> ExportV3Snapshot {
        try builder.build(area: area, tracks: tracks(), exportedAt: 70000)
    }
    func originalPhotos() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: base.track.photos.map { ($0.filePath, try base.photos.read(relativePath: $0.filePath)) })
    }
    func key(_ id: UUID) -> String { id.uuidString.lowercased() }
    func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func dispose() { base.dispose() }
}

@MainActor
private extension Stage4Fixture {
    func captureForStage5() throws -> CapturedTrackPhoto {
        try #require(try coordinator.freezePhotoCapture(.success(jpegData: jpeg, capturedAt: clock.wall)))
    }
}

private final class Stage5FailingFS: ExportStagingFileSystem {
    let local = LocalExportStagingFileSystem()
    var writes = 0
    func fileExists(at url: URL) -> Bool { local.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try local.createDirectory(at: url) }
    func removeItem(at url: URL) throws { try local.removeItem(at: url) }
    func write(_ data: Data, to url: URL) throws {
        writes += 1
        if writes == 2 { throw CocoaError(.fileWriteUnknown) }
        try local.write(data, to: url)
    }
}

private struct Stage5SymlinkFS: ExportStagingFileSystem {
    let session: String
    let outside: URL
    let local = LocalExportStagingFileSystem()
    func fileExists(at url: URL) -> Bool { local.fileExists(at: url) }
    func createDirectory(at url: URL) throws {
        try local.createDirectory(at: url)
        if url.lastPathComponent == session {
            try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("tracks"), withDestinationURL: outside)
        }
    }
    func removeItem(at url: URL) throws { try local.removeItem(at: url) }
    func write(_ data: Data, to url: URL) throws { try local.write(data, to: url) }
}

enum Stage5ZIP {
    // Independent test reader validates local headers, central references, EOCD and CRC32.
    static func read(_ url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        var cursor = 0, result: [String: Data] = [:], offsets: [String: Int] = [:]
        func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        while cursor + 30 <= data.count, u32(cursor) == 0x04034b50 {
            let size = u32(cursor + 18), nameLength = u16(cursor + 26), extraLength = u16(cursor + 28)
            let start = cursor + 30 + nameLength + extraLength, end = start + size
            guard end <= data.count, u16(cursor + 8) == 0, u32(cursor + 22) == size else { throw Stage5ZIPError.invalid }
            let name = String(decoding: data[(cursor + 30)..<(cursor + 30 + nameLength)], as: UTF8.self)
            let bytes = Data(data[start..<end])
            guard result[name] == nil, ArchivePathValidator.isSafe(name), u32(cursor + 14) == crc(bytes) else { throw Stage5ZIPError.invalid }
            result[name] = bytes
            offsets[name] = cursor
            cursor = end
        }
        let centralStart = cursor
        var centralNames = Set<String>()
        while cursor + 46 <= data.count, u32(cursor) == 0x02014b50 {
            let nameLength = u16(cursor + 28), end = cursor + 46 + nameLength + u16(cursor + 30) + u16(cursor + 32)
            guard end <= data.count else { throw Stage5ZIPError.invalid }
            let name = String(decoding: data[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            guard let bytes = result[name], offsets[name] == u32(cursor + 42), u32(cursor + 16) == crc(bytes),
                  u32(cursor + 20) == bytes.count, u32(cursor + 24) == bytes.count,
                  centralNames.insert(name).inserted else { throw Stage5ZIPError.invalid }
            cursor = end
        }
        guard cursor + 22 == data.count, u32(cursor) == 0x06054b50,
              u16(cursor + 8) == result.count, u16(cursor + 10) == result.count,
              u32(cursor + 12) == cursor - centralStart, u32(cursor + 16) == centralStart,
              centralNames == Set(result.keys) else { throw Stage5ZIPError.invalid }
        return result
    }
    private static func crc(_ bytes: Data) -> Int {
        var value = UInt32.max
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = value & 1 == 1 ? (value >> 1) ^ 0xedb88320 : value >> 1 }
        }
        return Int(value ^ UInt32.max)
    }
}
private enum Stage5ZIPError: Error { case invalid }
