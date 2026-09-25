import Foundation
import Testing
@testable import RoomMarker

@Suite("Phase 7 ZIP export and sharing")
@MainActor
struct Phase7ExportTests {
    @Test("1. Valid staging directory produces a ZIP")
    func validStagingProducesZIP() throws {
        try withArchiveFixture { fixture in
            let result = try fixture.archive()
            #expect(FileManager.default.fileExists(atPath: result.archiveURL.path))
            #expect(result.archiveURL.pathExtension == "zip")
        }
    }

    @Test("2. ZIP contains manifest.json")
    func containsManifest() throws {
        try withArchiveFixture { fixture in
            let archive = try fixture.archive()
            let names = try ZIPTestReader.read(archive.archiveURL).map(\.name)
            #expect(names.contains("manifest.json"))
        }
    }

    @Test("3. ZIP contains every Track JSON")
    func containsTracks() throws {
        try withArchiveFixture(trackCount: 2) { fixture in
            let names = try ZIPTestReader.read(fixture.archive().archiveURL).map(\.name)
            #expect(names.contains("tracks/00000000-0000-0000-0000-000000000001.json"))
            #expect(names.contains("tracks/00000000-0000-0000-0000-000000000002.json"))
        }
    }

    @Test("4. ZIP contains expected photos")
    func containsPhotos() throws {
        try withArchiveFixture(includePhoto: true) { fixture in
            let entries = try ZIPTestReader.read(fixture.archive().archiveURL)
            #expect(entries.first { $0.name.hasPrefix("photos/") }?.data == fixture.photoBytes)
        }
    }

    @Test("5. Session parent directory is not archived")
    func excludesSessionParent() throws {
        try withArchiveFixture { fixture in
            let result = try fixture.archive()
            let names = try ZIPTestReader.read(result.archiveURL).map(\.name)
            #expect(names.allSatisfy { !$0.contains(fixture.staging.sessionDirectory.lastPathComponent) })
        }
    }

    @Test("6. All archive entries are relative safe paths")
    func safeRelativeEntries() throws {
        try withArchiveFixture(includePhoto: true) { fixture in
            let names = try ZIPTestReader.read(fixture.archive().archiveURL).map(\.name)
            #expect(names.allSatisfy(ArchivePathValidator.isSafe))
        }
    }

    @Test("7. Traversal archive entry is rejected")
    func traversalRejected() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source")
            try Data("x".utf8).write(to: source)
            let destination = root.appendingPathComponent("bad.zip")
            #expect(throws: ZIPArchiveError.unsafeEntryPath("../bad")) {
                try StoredZIPWriter().write(
                    entries: [ZIPSourceEntry(archivePath: "../bad", sourceURL: source)],
                    to: destination
                )
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test("8. Absolute archive entry is rejected")
    func absoluteRejected() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source")
            try Data("x".utf8).write(to: source)
            #expect(throws: ZIPArchiveError.unsafeEntryPath("/bad")) {
                try StoredZIPWriter().write(
                    entries: [ZIPSourceEntry(archivePath: "/bad", sourceURL: source)],
                    to: root.appendingPathComponent("bad.zip")
                )
            }
        }
    }

    @Test("9. Logical archive entry order is deterministic")
    func deterministicOrder() throws {
        try withArchiveFixture(trackCount: 2, includePhoto: true) { fixture in
            let names = try ZIPTestReader.read(fixture.archive().archiveURL).map(\.name)
            #expect(names == [
                "manifest.json",
                "tracks/00000000-0000-0000-0000-000000000001.json",
                "tracks/00000000-0000-0000-0000-000000000002.json",
                "photos/00000000-0000-0000-0000-000000000001/photo.jpg",
            ])
        }
    }

    @Test("10. Empty Area exports a manifest-only ZIP")
    func emptyAreaExport() throws {
        try withTemporaryDirectory { root in
            let snapshot = AreaExportSnapshot(
                area: ExportAreaSnapshot(id: id(50), name: "Empty"),
                exportedAt: 1,
                tracks: []
            )
            let staging = try ExportStagingService(baseDirectory: root.appendingPathComponent("stage"))
                .stage(snapshot, sessionID: id(60))
            let result = try StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("archives"))
                .createArchive(from: staging, areaName: "Empty", exportedAt: 1, archiveID: id(61))
            let names = try ZIPTestReader.read(result.archiveURL).map(\.name)
            #expect(names == ["manifest.json"])
        }
    }

    @Test("11. Completed Track remains completed in ZIP")
    func completedTrackZIP() throws {
        try withArchiveFixture(endedAt: 20) { fixture in
            let track = try decodedTrack(from: fixture.archive().archiveURL)
            #expect(track.endedAt == 20)
        }
    }

    @Test("12. Incomplete Track remains incomplete in ZIP")
    func incompleteTrackZIP() throws {
        try withArchiveFixture(endedAt: nil) { fixture in
            let track = try decodedTrack(from: fixture.archive().archiveURL)
            #expect(track.endedAt == nil)
        }
    }

    @Test("13. Conceptual unassigned export has no persisted Area identifier")
    func unassignedZIP() throws {
        try withArchiveFixture(area: ExportAreaSnapshot(id: nil, name: "未分区")) { fixture in
            let entries = try ZIPTestReader.read(fixture.archive().archiveURL)
            let manifestData = try #require(entries.first { $0.name == "manifest.json" }?.data)
            let manifest = try JSONDecoder().decode(ExportManifestDTO.self, from: manifestData)
            #expect(manifest.area.name == "未分区")
            #expect(manifest.area.sourceId == nil)
        }
    }

    @Test("14. Safe filename is human-readable and unique")
    func safeFilename() {
        let filename = ExportArchiveFilename.make(areaName: "教学楼A", exportedAt: 0, archiveID: id(1))
        #expect(filename == "RoomMarker-教学楼A-19700101-000000-00000000.zip")
    }

    @Test("15. Filename sanitization removes separators and punctuation")
    func filenameSanitization() {
        let filename = ExportArchiveFilename.make(areaName: " ../A:B\\C/ ", exportedAt: 0, archiveID: id(1))
        #expect(!filename.contains("/"))
        #expect(!filename.contains("\\"))
        #expect(!filename.contains(":"))
        #expect(filename.hasSuffix(".zip"))
    }

    @Test("16. Filename collision produces a distinct archive")
    func filenameCollision() throws {
        try withArchiveFixture { fixture in
            let first = try fixture.archive(archiveID: id(88))
            let second = try fixture.archive(archiveID: id(88))
            #expect(first.archiveURL != second.archiveURL)
            #expect(second.archiveURL.lastPathComponent.contains("-2.zip"))
        }
    }

    @Test("17. Archive failure removes partial ZIP output")
    func failureRemovesPartial() throws {
        try withTemporaryDirectory { root in
            let invalidSource = root.appendingPathComponent("directory", isDirectory: true)
            try FileManager.default.createDirectory(at: invalidSource, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("failed.zip")
            #expect(throws: ZIPArchiveError.self) {
                try StoredZIPWriter().write(
                    entries: [ZIPSourceEntry(archivePath: "bad", sourceURL: invalidSource)],
                    to: destination
                )
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathExtension("partial").path))
        }
    }

    @Test("18. Staging failure produces no ZIP")
    func stagingFailureProducesNoZIP() throws {
        try withTemporaryDirectory { root in
            let snapshot = simpleSnapshot()
            let fileSystem = Phase7FailingStagingFileSystem()
            let staging = ExportStagingService(
                baseDirectory: root.appendingPathComponent("stage"),
                fileSystem: fileSystem
            )
            #expect(throws: ExportValidationError.self) {
                try staging.stage(snapshot, sessionID: id(1))
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("archives").path))
        }
    }

    @Test("19. Original photo survives successful ZIP creation")
    func sourcePhotoSurvivesSuccess() throws {
        try withArchiveFixture(includePhoto: true) { fixture in
            _ = try fixture.archive()
            #expect(fixture.originalPhoto == fixture.photoBytes)
        }
    }

    @Test("20. Original photo survives failed ZIP creation")
    func sourcePhotoSurvivesFailure() throws {
        try withArchiveFixture(includePhoto: true) { fixture in
            try FileManager.default.removeItem(at: fixture.staging.manifestURL)
            #expect(throws: ZIPArchiveError.self) { try fixture.archive() }
            #expect(fixture.originalPhoto == fixture.photoBytes)
        }
    }

    @Test("21. End-to-end export does not mutate SwiftData models")
    func swiftDataUnchanged() throws {
        let store = Phase7PhotoStore()
        let area = Area(name: "Area", createdAt: 1)
        let track = Track(name: "Track", area: area, startedAt: 2, endedAt: 3)
        track.points = [TrackPoint(track: track, timeMs: 2)]
        area.tracks = [track]
        let before = (area.name, track.name, track.points.map(\.id), track.endedAt)
        try withTemporaryDirectory { root in
            let snapshot = try AreaExportSnapshotBuilder(photoStorage: store) { _ in true }
                .build(area: area, exportedAt: 4)
            let staging = try ExportStagingService(baseDirectory: root.appendingPathComponent("stage"))
                .stage(snapshot, sessionID: id(4))
            _ = try StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("archives"))
                .createArchive(from: staging, areaName: area.name, exportedAt: 4, archiveID: id(5))
        }
        #expect(area.name == before.0)
        #expect(track.name == before.1)
        #expect(track.points.map(\.id) == before.2)
        #expect(track.endedAt == before.3)
    }

    @Test("22. Duplicate export start is rejected")
    func duplicateStartRejected() throws {
        let fixture = coordinatorFixture()
        try fixture.coordinator.start(area: fixture.area)
        #expect(throws: ExportWorkflowError.exportAlreadyInProgress) {
            try fixture.coordinator.start(area: fixture.area)
        }
        fixture.coordinator.cancelAndReset()
    }

    @Test("23. Successful state transitions are explicit and ordered")
    func stateTransitions() async throws {
        let fixture = coordinatorFixture()
        try fixture.coordinator.start(area: fixture.area)
        await fixture.coordinator.waitForCurrentExport()
        #expect(fixture.coordinator.stateHistory.map(stateName) == [
            "idle", "preparing", "staging", "archiving", "ready",
        ])
    }

    @Test("24. Successful export reaches readyToShare")
    func reachesReadyToShare() async throws {
        let fixture = coordinatorFixture()
        try fixture.coordinator.start(area: fixture.area)
        await fixture.coordinator.waitForCurrentExport()
        guard case let .readyToShare(result) = fixture.coordinator.state else {
            Issue.record("Expected readyToShare")
            return
        }
        #expect(result.archiveURL.pathExtension == "zip")
    }

    @Test("25. Archive failure reaches failed state")
    func reachesFailed() async throws {
        let fixture = coordinatorFixture(archiveService: Phase7FailingArchiveService())
        try fixture.coordinator.start(area: fixture.area)
        await fixture.coordinator.waitForCurrentExport()
        guard case let .failed(failure) = fixture.coordinator.state else {
            Issue.record("Expected failed")
            return
        }
        #expect(failure.title == "无法创建压缩包")
    }

    @Test("26. Reset after Share Sheet removes temporary archive")
    func resetCleanup() async throws {
        let archive = Phase7ArchiveService()
        let fixture = coordinatorFixture(archiveService: archive)
        try fixture.coordinator.start(area: fixture.area)
        await fixture.coordinator.waitForCurrentExport()
        fixture.coordinator.resetAfterSharing()
        #expect(fixture.coordinator.state == .idle)
        #expect(archive.removedURLs.count == 1)
    }

    @Test("27. Stale cleanup only touches owned export root")
    func staleCleanupScope() throws {
        try withTemporaryDirectory { parent in
            let owned = parent.appendingPathComponent("RoomMarkerExports", isDirectory: true)
            let stale = owned.appendingPathComponent("stale", isDirectory: true)
            let unrelated = parent.appendingPathComponent("keep.txt")
            try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: unrelated)
            try ExportTemporaryCleaner(ownedRoot: owned).removeStaleOwnedExports()
            #expect(!FileManager.default.fileExists(atPath: stale.path))
            #expect(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }

    @Test("28. Share Sheet payload contains final ZIP only")
    func sharePayloadOnlyZIP() {
        let result = ZIPArchiveResult(
            archiveURL: URL(fileURLWithPath: "/tmp/final.zip"),
            entryPaths: ["manifest.json"]
        )
        let payload = ExportSharePayload(result: result)
        #expect(payload.items == [result.archiveURL])
        #expect(payload.items.count == 1)
    }

    @Test("29. Complete end-to-end fixture preserves contract and bytes")
    func endToEndFixture() throws {
        let photos = Phase7PhotoStore()
        let area = Area(id: id(70), name: "导出压缩测试区", createdAt: 1)
        let track = Track(id: id(71), name: "ZIP测试轨迹", area: area, startedAt: 10, endedAt: 30)
        track.points = [TrackPoint(track: track, timeMs: 20, pressureHpa: 1008)]
        track.tags = [TrackTag(track: track, timeMs: 21, tagType: .door, note: "ZIP测试门", createdAt: 21)]
        let photoPath = "photos/\(track.id.uuidString.lowercased())/fixture.jpg"
        let photo = TrackPhoto(track: track, timeMs: 22, filePath: photoPath, createdAt: 22)
        track.photos = [photo]
        area.tracks = [track]
        let photoBytes = Data([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9])
        photos.data[photoPath] = photoBytes

        try withTemporaryDirectory { root in
            let snapshot = try AreaExportSnapshotBuilder(photoStorage: photos) { _ in true }
                .build(area: area, exportedAt: 40)
            let staging = try ExportStagingService(baseDirectory: root.appendingPathComponent("stage"))
                .stage(snapshot, sessionID: id(72))
            let archive = try StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("archives"))
                .createArchive(from: staging, areaName: area.name, exportedAt: 40, archiveID: id(73))
            let entries = try ZIPTestReader.read(archive.archiveURL)
            let manifest = try JSONDecoder().decode(
                ExportManifestDTO.self,
                from: try #require(entries.first { $0.name == "manifest.json" }?.data)
            )
            let exportedTrack = try JSONDecoder().decode(
                ExportedTrackDTO.self,
                from: try #require(entries.first { $0.name.hasPrefix("tracks/") }?.data)
            )
            #expect(manifest.trackCount == 1)
            #expect(manifest.capabilities?.nearbyWifiFingerprint == .unsupported)
            #expect(exportedTrack.pointCount == exportedTrack.points.count)
            #expect(exportedTrack.tags.first?.note == "ZIP测试门")
            #expect(exportedTrack.points.first?.wifiCount == nil)
            #expect(exportedTrack.points.first?.wifiTop == nil)
            #expect(entries.first { $0.name == photoPath }?.data == photoBytes)
            #expect(photos.data[photoPath] == photoBytes)
        }
    }

    private func decodedTrack(from archive: URL) throws -> ExportedTrackDTO {
        let entry = try #require(ZIPTestReader.read(archive).first { $0.name.hasPrefix("tracks/") })
        return try JSONDecoder().decode(ExportedTrackDTO.self, from: entry.data)
    }

    private func coordinatorFixture(
        archiveService: any ZIPArchiveCreating = Phase7ArchiveService()
    ) -> CoordinatorFixture {
        let root = temporaryDirectoryURL()
        let photos = Phase7PhotoStore()
        let area = Area(name: "Area", createdAt: 1)
        let track = Track(name: "Track", area: area, startedAt: 1, endedAt: 2)
        area.tracks = [track]
        let coordinator = AreaExportCoordinator(
            photoStorage: photos,
            stagingService: ExportStagingService(baseDirectory: root.appendingPathComponent("stage")),
            archiveService: archiveService,
            nowMilliseconds: { 10 },
            makeSessionID: { id(90) }
        )
        return CoordinatorFixture(area: area, coordinator: coordinator)
    }

    private func withArchiveFixture(
        trackCount: Int = 1,
        includePhoto: Bool = false,
        endedAt: Int64? = 20,
        area: ExportAreaSnapshot? = nil,
        _ body: (ArchiveFixture) throws -> Void
    ) throws {
        try withTemporaryDirectory { root in
            let exportArea = area ?? ExportAreaSnapshot(id: id(50), name: "Area")
            let tracks = (1...trackCount).map { index in
                TrackExportSnapshot(
                    id: id(index),
                    name: "Track \(index)",
                    startedAt: Int64(index),
                    endedAt: endedAt,
                    points: [],
                    tags: [],
                    photos: includePhoto && index == 1 ? [TrackPhotoExportSnapshot(
                        id: id(80),
                        timeMs: 3,
                        relativePath: "photos/\(id(1).uuidString.lowercased())/photo.jpg",
                        note: "",
                        latitude: nil,
                        longitude: nil,
                        altitude: nil,
                        headingDeg: nil,
                        createdAt: 3,
                        jpegData: Data([1, 2, 3])
                    )] : []
                )
            }
            let snapshot = AreaExportSnapshot(area: exportArea, exportedAt: 10, tracks: tracks)
            let stagingService = ExportStagingService(baseDirectory: root.appendingPathComponent("stage"))
            let staging = try stagingService.stage(snapshot, sessionID: id(51))
            let archiveService = StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("archives"))
            try body(ArchiveFixture(
                staging: staging,
                archiveService: archiveService,
                areaName: exportArea.name,
                photoBytes: Data([1, 2, 3]),
                originalPhoto: includePhoto ? Data([1, 2, 3]) : nil
            ))
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(root)
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomMarkerPhase7-\(UUID().uuidString)", isDirectory: true)
    }

    private func simpleSnapshot() -> AreaExportSnapshot {
        AreaExportSnapshot(
            area: ExportAreaSnapshot(id: id(50), name: "Area"),
            exportedAt: 1,
            tracks: []
        )
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func stateName(_ state: AreaExportState) -> String {
        switch state {
        case .idle: "idle"
        case .preparingSnapshot: "preparing"
        case .staging: "staging"
        case .archiving: "archiving"
        case .readyToShare: "ready"
        case .failed: "failed"
        }
    }
}

private struct ArchiveFixture {
    let staging: ExportStagingResult
    let archiveService: StoredZIPArchiveService
    let areaName: String
    let photoBytes: Data
    let originalPhoto: Data?

    func archive(archiveID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!) throws -> ZIPArchiveResult {
        try archiveService.createArchive(
            from: staging,
            areaName: areaName,
            exportedAt: 10,
            archiveID: archiveID
        )
    }
}

private struct CoordinatorFixture {
    let area: Area
    let coordinator: AreaExportCoordinator
}

@MainActor
private final class Phase7PhotoStore: PhotoFileStoring {
    var data: [String: Data] = [:]

    func storeJPEG(_ value: Data, trackID: UUID, timeMs: Int64) throws -> String {
        let path = "photos/\(trackID.uuidString.lowercased())/\(timeMs).jpg"
        data[path] = value
        return path
    }

    func validate(relativePath: String) throws {
        guard ArchivePathValidator.isSafe(relativePath), relativePath.hasPrefix("photos/") else {
            throw PhotoStorageError.unsafeRelativePath
        }
    }

    func read(relativePath: String) throws -> Data {
        guard let value = data[relativePath] else { throw PhotoStorageError.missingFile }
        return value
    }

    func delete(relativePath: String) throws { data.removeValue(forKey: relativePath) }
    func deleteTrackDirectory(trackID: UUID) throws {}
}

private final class Phase7FailingStagingFileSystem: ExportStagingFileSystem {
    func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func write(_ data: Data, to url: URL) throws { throw CocoaError(.fileWriteUnknown) }
    func removeItem(at url: URL) throws { try FileManager.default.removeItem(at: url) }
}

@MainActor
private final class Phase7ArchiveService: ZIPArchiveCreating {
    private(set) var removedURLs: [URL] = []

    func createArchive(
        from staging: ExportStagingResult,
        areaName: String,
        exportedAt: Int64,
        archiveID: UUID
    ) throws -> ZIPArchiveResult {
        let url = staging.sessionDirectory.deletingLastPathComponent()
            .appendingPathComponent("\(archiveID.uuidString).zip")
        try Data("zip".utf8).write(to: url)
        return ZIPArchiveResult(archiveURL: url, entryPaths: ["manifest.json"])
    }

    func removeArchive(at url: URL) throws {
        removedURLs.append(url)
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
private final class Phase7FailingArchiveService: ZIPArchiveCreating {
    func createArchive(
        from staging: ExportStagingResult,
        areaName: String,
        exportedAt: Int64,
        archiveID: UUID
    ) throws -> ZIPArchiveResult {
        throw ZIPArchiveError.outputFailure("synthetic")
    }

    func removeArchive(at url: URL) throws {}
}

private struct ZIPTestEntry: Equatable {
    let name: String
    let data: Data
}

private enum ZIPTestReader {
    static func read(_ url: URL) throws -> [ZIPTestEntry] {
        let bytes = try Data(contentsOf: url)
        var offset = 0
        var entries: [ZIPTestEntry] = []
        while offset + 4 <= bytes.count, uint32(bytes, offset) == 0x0403_4B50 {
            let method = uint16(bytes, offset + 8)
            guard method == 0 else { throw ZIPTestError.unsupportedCompression }
            let size = Int(uint32(bytes, offset + 18))
            let nameLength = Int(uint16(bytes, offset + 26))
            let extraLength = Int(uint16(bytes, offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            let dataEnd = dataStart + size
            guard dataEnd <= bytes.count else { throw ZIPTestError.truncated }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries.append(ZIPTestEntry(name: name, data: Data(bytes[dataStart..<dataEnd])))
            offset = dataEnd
        }
        return entries
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}

private enum ZIPTestError: Error {
    case unsupportedCompression
    case truncated
}
