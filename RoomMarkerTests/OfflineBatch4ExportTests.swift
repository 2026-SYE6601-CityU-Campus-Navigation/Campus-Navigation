import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Offline batch 4 selection, streaming and HTML", .serialized)
@MainActor
struct OfflineBatch4ExportTests {
    @Test("Selected IDs distinguish duplicate names and retain whole cross-building evidence")
    func selected() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let other = Track(name: f.base.track.name, startedAt: 1, endedAt: 2)
        let spare = Area(name: "Not selected", createdAt: 1)
        f.base.context.insert(other); f.base.context.insert(spare)
        try f.base.context.save()
        let value = try f.builder.build(tracks: f.tracks(), exportedAt: 70000, selectedIDs: [f.base.track.id])
        #expect(value.manifest.scope.kind == "selected" && value.manifest.scope.trackIds == [f.id])
        #expect(try value.tracks == f.snapshot(area: f.a).tracks)
        #expect(Set(value.manifest.areas.map(\.id)) == [f.key(f.a.id), f.key(f.b.id)])
        #expect(value.manifest.trackCount == 1 && !f.base.context.hasChanges)
    }

    @Test("Empty, disappeared and active selections fail, never silently exporting a subset", arguments: ["empty", "missing", "active"])
    func invalidSelection(_ kind: String) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let ids: Set<UUID> = kind == "empty" ? [] : kind == "missing" ? [f.base.track.id, UUID()] : [f.base.track.id]
        #expect(throws: (any Error).self) {
            try f.builder.build(tracks: f.tracks(), exportedAt: 70000,
                activeTrackID: kind == "active" ? f.base.track.id : nil, selectedIDs: ids)
        }
        #expect(!f.base.context.hasChanges)
    }

    @Test("Prepared worker matches reference DTOs and original JPEGs byte for byte")
    func streamingEquivalence() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let originals = try f.originalPhotos(), reference = try f.snapshot()
        let payloads = Dictionary(uniqueKeysWithValues: f.base.track.imuBatches.map { ($0.id, $0.payload) })
        let prepared = try prepare(f)
        #expect(prepared.skeleton.photos.isEmpty && prepared.skeleton.tracks[0].imu.batches.allSatisfy { $0.samples.isEmpty })
        let root = f.stageRoot
        let staged = try await Task.detached { try V3StreamingExporter.stage(prepared, base: root, sessionID: UUID()) }.value
        defer { try? f.staging.cleanUp(staged.staging) }
        #expect(!staged.metrics.ranOnMainThread && staged.metrics.encodedIMUSamples == 4)
        #expect(staged.metrics.maxDecodedIMUSamples == 4 && staged.metrics.copiedPhotoCount == 4 && staged.metrics.maxCopyChunkBytes <= 65536)
        let track = try JSONDecoder().decode(ExportV3Track.self, from: Data(contentsOf: #require(staged.staging.trackURLs.first)))
        #expect(track == reference.tracks[0])
        var expected = reference.manifest; expected.photoIndex = "index.html"
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: Data(contentsOf: staged.staging.manifestURL))
        #expect(manifest == expected)
        let zip = try f.archive.createArchive(from: staged.staging, areaName: "Synthetic receiver", exportedAt: 70000)
        let entries = try Stage5ZIP.read(zip.archiveURL)
        #expect(entries.count == 7 && entries["index.html"] != nil)
        for photo in track.photos { #expect(entries[photo.file] == originals[photo.file]) }
        #expect(try f.originalPhotos() == originals && !f.base.context.hasChanges)
        #expect(f.base.track.imuBatches.allSatisfy { payloads[$0.id] == $0.payload })
        // Synthetic-only bridge for independently exercising the desktop receiver.
        let artifact = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Batch4ReceiverSynthetic.zip")
        try Data(contentsOf: zip.archiveURL).write(to: artifact, options: .atomic)
    }

    @Test("Worker rejects corrupt payloads, inventory mismatch and changed/missing sources, cleaning only its session",
          arguments: ["payload", "inventory", "photo", "missing", "aliasEscape"])
    func workerFailures(_ defect: String) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let source = try prepare(f), originals = try f.originalPhotos()
        var payloads = source.imuPayloads, photos = source.photos
        let first = try #require(photos.keys.sorted().first)
        switch defect {
        case "payload": payloads[try #require(payloads.keys.first)] = Data("invalid".utf8)
        case "inventory": payloads[UUID().uuidString.lowercased()] = Data()
        case "photo": try Data("bad JPEG".utf8).write(to: #require(photos[first]?.url))
        case "missing": try f.base.photos.delete(relativePath: first)
        default:
            let outside = f.base.root.appendingPathComponent("outside.jpg")
            try f.base.jpeg.write(to: outside)
            photos[first] = .init(root: source.photos[first]!.root, url: outside)
        }
        let input = V3PreparedExport(skeleton: source.skeleton, imuPayloads: payloads, photos: photos)
        let root = f.stageRoot, id = UUID()
        let result = await Task.detached { Result { try V3StreamingExporter.stage(input, base: root, sessionID: id) } }.value
        if case .success = result { Issue.record("Unsafe/invalid payload accepted") }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(f.key(id)).path))
        #expect(f.base.track.photos.count == 4 && f.base.track.imuBatches.count == 1 && !f.base.context.hasChanges)
        if !["photo", "missing"].contains(defect) { #expect(try f.originalPhotos() == originals) }
    }

    @Test("Worker refuses existing/symlink session and preserves sentinel")
    func existingSession() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let input = try prepare(f), id = UUID(), root = f.stageRoot
        let directory = root.appendingPathComponent(f.key(id))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("sentinel")
        try Data([1, 2, 3]).write(to: sentinel)
        let result = await Task.detached { Result { try V3StreamingExporter.stage(input, base: root, sessionID: id) } }.value
        if case .success = result { Issue.record("Existing session overwritten") }
        #expect(try Data(contentsOf: sentinel) == Data([1, 2, 3]))
    }

    @Test("Static index escapes untrusted text and preserves independent and linked photo identity")
    func html() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let danger = "<script>alert(1)</script> & \" '"
        f.base.track.name = danger
        f.base.track.photos.first?.note = danger
        try f.base.context.save()
        let snapshot = try f.snapshot()
        let html = String(decoding: try PhotoHTMLIndex.make(manifest: snapshot.manifest, tracks: snapshot.tracks), as: UTF8.self)
        #expect(!html.contains("<script>") && html.contains("&lt;script&gt;") && html.contains("&amp;") && html.contains("&quot;") && html.contains("&#39;"))
        #expect(html.contains("Content-Security-Policy") && !html.contains("https://"))
        #expect(html.contains("节点照片") && html.contains("独立风景") && html.contains("历史独立照片"))
        #expect(html.components(separatedBy: "<img ").count - 1 == 4)
    }

    @Test("Unsafe portable archive paths rejected without weakening original containment", arguments: ["C:/photo.jpg", "a\u{0}b", "a\nb", "a\\b", "../x", "/tmp/x", "a//b"])
    func portablePaths(_ path: String) { #expect(!ArchivePathValidator.isSafe(path)) }

    @Test("Legacy v3 requires neither selected IDs nor HTML index")
    func legacyManifest() throws {
        let value = try JSONDecoder().decode(ExportV3Manifest.self, from: TestFixtures.data(named: "stage5_legacy_manifest_v3"))
        #expect(value.photoIndex == nil && value.scope.trackIds == nil)
    }

    @Test("Selected production workflow uses worker, shares one archive and preserves originals")
    func selectedWorkflow() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let source = try f.originalPhotos()
        let coordinator = AreaExportCoordinator(photoStorage: f.base.photos, stagingService: f.staging, archiveService: f.archive)
        try coordinator.startSelectedV3(ids: [f.base.track.id], tracks: f.tracks())
        await coordinator.waitForCurrentExport()
        guard case let .readyToShare(zip) = coordinator.state else { Issue.record("Expected selected ZIP: \(coordinator.state)"); return }
        #expect(coordinator.lastStreamingMetrics?.ranOnMainThread == false)
        #expect(ExportSharePayload(result: zip).items.count == 1)
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: #require(Stage5ZIP.read(zip.archiveURL)["manifest.json"]))
        #expect(manifest.scope.trackIds == [f.id] && manifest.photoIndex == "index.html")
        coordinator.resetAfterSharing()
        #expect(try f.originalPhotos() == source && !f.base.context.hasChanges)
    }

    @Test("Cancelled worker cleans partial export and leaves subsequent generation shareable")
    func cancelWorkerAndRestart() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let coordinator = AreaExportCoordinator(photoStorage: f.base.photos, stagingService: f.staging, archiveService: f.archive)
        try coordinator.startAllV3(tracks: f.tracks())
        let old = Task { await coordinator.waitForCurrentExport() }
        while coordinator.state == .preparingSnapshot { await Task.yield() }
        #expect(coordinator.state.isBusy)
        coordinator.cancelAndReset()
        try coordinator.startSelectedV3(ids: [f.base.track.id], tracks: f.tracks())
        await old.value
        await coordinator.waitForCurrentExport()
        guard case let .readyToShare(zip) = coordinator.state else { Issue.record("Expected new generation"); return }
        #expect(FileManager.default.fileExists(atPath: zip.archiveURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.stageRoot.path).isEmpty)
        #expect(!f.base.context.hasChanges && f.base.track.photos.count == 4)
    }

    private func prepare(_ f: Stage5Fixture) throws -> V3PreparedExport {
        let preparation = V3ExportPreparation()
        let skeleton = try f.builder.build(tracks: f.tracks(), exportedAt: 70000, preparation: preparation)
        return preparation.freeze(skeleton)
    }
}
