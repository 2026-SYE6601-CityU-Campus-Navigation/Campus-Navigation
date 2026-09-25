import Foundation
import Testing
@testable import RoomMarker

@Suite("Phase 6 immutable export")
@MainActor
struct Phase6ExportTests {
    @Test("1. Snapshot remains immutable after model mutation")
    func immutableSnapshot() throws {
        let fixture = makeFixture()
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 900)

        fixture.track.name = "Mutated"
        fixture.track.points.removeAll()
        fixture.area.name = "Mutated Area"

        #expect(snapshot.area.name == "Area")
        #expect(snapshot.tracks.first?.name == "Track")
        #expect(snapshot.tracks.first?.pointCount == 2)
    }

    @Test("2. Tracks sort by start time then UUID")
    func trackOrdering() throws {
        let fixture = makeFixture(includeDefaults: false)
        let laterID = id(2)
        let earlierTieID = id(1)
        let laterTieID = id(3)
        fixture.area.tracks = [
            Track(id: laterID, name: "B", area: fixture.area, startedAt: 20),
            Track(id: laterTieID, name: "C", area: fixture.area, startedAt: 10),
            Track(id: earlierTieID, name: "A", area: fixture.area, startedAt: 10),
        ]

        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 900)

        #expect(snapshot.tracks.map(\.id) == [earlierTieID, laterTieID, laterID])
    }

    @Test("3. Points sort by time then UUID")
    func pointOrdering() throws {
        let fixture = makeFixture(includeDefaults: false)
        let firstID = id(1)
        let secondID = id(2)
        fixture.track.points = [
            TrackPoint(id: secondID, track: fixture.track, timeMs: 20),
            TrackPoint(id: id(3), track: fixture.track, timeMs: 30),
            TrackPoint(id: firstID, track: fixture.track, timeMs: 20),
        ]
        fixture.area.tracks = [fixture.track]

        let track = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first)
        #expect(track.points.map(\.id) == [firstID, secondID, id(3)])
    }

    @Test("4. Tags sort by time, creation time, then UUID")
    func tagOrdering() throws {
        let fixture = makeFixture(includeDefaults: false)
        fixture.track.tags = [
            tag(id: id(3), track: fixture.track, time: 20, created: 20),
            tag(id: id(2), track: fixture.track, time: 10, created: 20),
            tag(id: id(1), track: fixture.track, time: 10, created: 10),
        ]
        fixture.area.tracks = [fixture.track]

        let track = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first)
        #expect(track.tags.map(\.id) == [id(1), id(2), id(3)])
    }

    @Test("5. Photos sort by time, creation time, then UUID")
    func photoOrdering() throws {
        let fixture = makeFixture(includeDefaults: false)
        let photos = [
            photo(id: id(3), track: fixture.track, time: 20, created: 20),
            photo(id: id(2), track: fixture.track, time: 10, created: 20),
            photo(id: id(1), track: fixture.track, time: 10, created: 10),
        ]
        fixture.track.photos = photos
        fixture.area.tracks = [fixture.track]
        for item in photos { fixture.photos.data[item.filePath] = Data([1]) }

        let track = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first)
        #expect(track.photos.map(\.id) == [id(1), id(2), id(3)])
    }

    @Test("6. Equal tag timestamps use UUID as final tie-breaker")
    func equalTimestampTieBreak() throws {
        let fixture = makeFixture(includeDefaults: false)
        fixture.track.tags = [
            tag(id: id(2), track: fixture.track, time: 10, created: 10),
            tag(id: id(1), track: fixture.track, time: 10, created: 10),
        ]
        fixture.area.tracks = [fixture.track]

        let track = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first)
        #expect(track.tags.map(\.id) == [id(1), id(2)])
    }

    @Test("7. Exported pointCount is derived from exported points")
    func derivedPointCount() throws {
        let fixture = makeFixture()
        let track = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first)
        let dto = ExportDTOMapper().track(from: track, areaName: fixture.area.name)

        #expect(dto.pointCount == dto.points.count)
        #expect(dto.pointCount == 2)
        #expect(throws: Never.self) { try ExportContractValidator.validate(track: dto, trackID: track.id) }
    }

    @Test("8. Incomplete Track preserves a nil endedAt")
    func incompleteTrack() throws {
        let fixture = makeFixture()
        fixture.track.endedAt = nil

        let track = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first)
        #expect(track.endedAt == nil)
        #expect(ExportDTOMapper().track(from: track, areaName: "Area").endedAt == nil)
    }

    @Test("9. Missing sensor values remain nil")
    func nilSensorValues() throws {
        let fixture = makeFixture(includeDefaults: false)
        fixture.track.points = [TrackPoint(track: fixture.track, timeMs: 10)]
        fixture.area.tracks = [fixture.track]

        let point = try #require(try fixture.builder.build(area: fixture.area, exportedAt: 1).tracks.first?.points.first)
        #expect(point.latitude == nil)
        #expect(point.pressureHpa == nil)
        #expect(point.headingDeg == nil)
    }

    @Test("10. Non-finite sensor values are rejected")
    func nonFiniteRejected() {
        let fixture = makeFixture(includeDefaults: false)
        let pointID = id(9)
        fixture.track.points = [TrackPoint(id: pointID, track: fixture.track, timeMs: 10, latitude: .nan)]
        fixture.area.tracks = [fixture.track]

        #expect(throws: ExportValidationError.nonFiniteSensorValue(
            trackID: fixture.track.id,
            recordID: pointID,
            field: "latitude"
        )) {
            try fixture.builder.build(area: fixture.area, exportedAt: 1)
        }
    }

    @Test("11. HarmonyOS v1 Wi-Fi fields remain decodable")
    func legacyWiFiFixture() throws {
        let data = try TestFixtures.data(named: "harmony_track_v1")
        let dto = try JSONDecoder().decode(ExportedTrackDTO.self, from: data)
        #expect(dto.version == 1)
        #expect(dto.points.first?.wifiCount == 2)
        #expect(dto.points.first?.wifiTop != nil)
    }

    @Test("12. iOS DTO never fabricates Wi-Fi observations")
    func noFabricatedWiFi() throws {
        let fixture = makeFixture()
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let dto = ExportDTOMapper().track(from: try #require(snapshot.tracks.first), areaName: "Area")
        #expect(dto.points.allSatisfy { $0.wifiCount == nil && $0.wifiTop == nil })
    }

    @Test("13. iOS v2 explicitly declares Wi-Fi unsupported")
    func explicitCapability() throws {
        let fixture = makeFixture()
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let dto = ExportDTOMapper().track(from: try #require(snapshot.tracks.first), areaName: "Area")
        #expect(dto.version == 2)
        #expect(dto.sourcePlatform == "ios")
        #expect(dto.capabilities?.nearbyWifiFingerprint == .unsupported)
    }

    @Test("14. All six tag raw values are preserved")
    func tagRawValues() throws {
        let fixture = makeFixture(includeDefaults: false)
        fixture.track.tags = TrackTagType.allCases.enumerated().map { index, type in
            TrackTag(track: fixture.track, timeMs: Int64(index), tagType: type, createdAt: Int64(index))
        }
        fixture.area.tracks = [fixture.track]

        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let dto = ExportDTOMapper().track(from: try #require(snapshot.tracks.first), areaName: "Area")
        #expect(dto.tags.map(\.tagType) == ["厕所", "楼梯", "门", "门禁", "电梯", "教室"])
    }

    @Test("15. Photo paths remain relative")
    func relativePhotoPath() throws {
        let fixture = makeFixture(includeDefaults: false)
        let item = photo(id: id(1), track: fixture.track, time: 10, created: 10)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]
        fixture.photos.data[item.filePath] = Data([1])

        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let path = try #require(snapshot.tracks.first?.photos.first?.relativePath)
        #expect(path.hasPrefix("photos/"))
        #expect(!path.hasPrefix("/"))
    }

    @Test("16. Absolute photo paths are rejected")
    func absolutePhotoRejected() {
        let fixture = makeFixture(includeDefaults: false)
        let item = TrackPhoto(track: fixture.track, timeMs: 1, filePath: "/tmp/a.jpg", createdAt: 1)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]

        #expect(throws: ExportValidationError.invalidPhotoPath(trackID: fixture.track.id, photoID: item.id)) {
            try fixture.builder.build(area: fixture.area, exportedAt: 1)
        }
    }

    @Test("17. Traversal photo paths are rejected")
    func traversalPhotoRejected() {
        let fixture = makeFixture(includeDefaults: false)
        let path = "photos/\(fixture.track.id.uuidString.lowercased())/../a.jpg"
        let item = TrackPhoto(track: fixture.track, timeMs: 1, filePath: path, createdAt: 1)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]

        #expect(throws: ExportValidationError.invalidPhotoPath(trackID: fixture.track.id, photoID: item.id)) {
            try fixture.builder.build(area: fixture.area, exportedAt: 1)
        }
    }

    @Test("18. Missing photo produces a typed failure")
    func missingPhotoRejected() {
        let fixture = makeFixture(includeDefaults: false)
        let item = photo(id: id(1), track: fixture.track, time: 1, created: 1)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]

        #expect(throws: ExportValidationError.missingPhotoFile(trackID: fixture.track.id, photoID: item.id)) {
            try fixture.builder.build(area: fixture.area, exportedAt: 1)
        }
    }

    @Test("19. Corrupt photo produces a typed failure")
    func corruptPhotoRejected() {
        let fixture = makeFixture(includeDefaults: false, validatesJPEG: false)
        let item = photo(id: id(1), track: fixture.track, time: 1, created: 1)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]
        fixture.photos.data[item.filePath] = Data([1])

        #expect(throws: ExportValidationError.corruptPhoto(trackID: fixture.track.id, photoID: item.id)) {
            try fixture.builder.build(area: fixture.area, exportedAt: 1)
        }
    }

    @Test("20. Staging copies photo bytes and preserves the source")
    func stagingCopiesPhoto() throws {
        let fixture = makeFixture(includeDefaults: false)
        let item = photo(id: id(1), track: fixture.track, time: 1, created: 1)
        let bytes = Data([1, 2, 3])
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]
        fixture.photos.data[item.filePath] = bytes
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)

        try withStaging { service, _ in
            let result = try service.stage(snapshot, sessionID: id(99))
            #expect(try Data(contentsOf: try #require(result.photoURLs.first)) == bytes)
            #expect(fixture.photos.data[item.filePath] == bytes)
            try service.cleanUp(result)
        }
    }

    @Test("21. Failed staging removes partial session output")
    func failedStagingCleansPartialOutput() throws {
        let fixture = makeFixture()
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FailingExportFileSystem(failOnWrite: 2)
        let service = ExportStagingService(baseDirectory: root, fileSystem: fileSystem)
        let sessionID = id(98)
        let session = root.appendingPathComponent(sessionID.uuidString.lowercased())

        #expect(throws: ExportValidationError.self) {
            try service.stage(snapshot, sessionID: sessionID)
        }
        #expect(!FileManager.default.fileExists(atPath: session.path))
        #expect(fileSystem.removeCalls == 1)
    }

    @Test("22. Manifest count matches snapshot")
    func manifestCount() throws {
        let fixture = makeFixture()
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let manifest = ExportDTOMapper().manifest(from: snapshot)
        #expect(manifest.trackCount == snapshot.tracks.count)
        #expect(manifest.tracks.count == snapshot.tracks.count)
    }

    @Test("23. Manifest preserves deterministic Track order")
    func manifestOrdering() throws {
        let fixture = makeFixture(includeDefaults: false)
        let a = Track(id: id(1), name: "A", area: fixture.area, startedAt: 1)
        let b = Track(id: id(2), name: "B", area: fixture.area, startedAt: 2)
        fixture.area.tracks = [b, a]
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)

        #expect(ExportDTOMapper().manifest(from: snapshot).tracks.map(\.name) == ["A", "B"])
    }

    @Test("24. Repeated unchanged exports produce equivalent JSON")
    func repeatedJSONEquivalent() throws {
        let fixture = makeFixture()
        let first = try fixture.builder.build(area: fixture.area, exportedAt: 50)
        let second = try fixture.builder.build(area: fixture.area, exportedAt: 50)
        let encoder = ExportJSONEncoder()
        let mapper = ExportDTOMapper()

        #expect(try encoder.encode(mapper.manifest(from: first)) == encoder.encode(mapper.manifest(from: second)))
        #expect(try encoder.encode(mapper.track(from: first.tracks[0], areaName: first.area.name)) ==
            encoder.encode(mapper.track(from: second.tracks[0], areaName: second.area.name)))
    }

    @Test("25. Unassigned export uses a conceptual area without persistence")
    func unassignedExport() throws {
        let fixture = makeFixture(includeDefaults: false)
        fixture.track.area = nil
        let snapshot = try fixture.builder.buildUnassigned(tracks: [fixture.track], exportedAt: 1)
        let manifest = ExportDTOMapper().manifest(from: snapshot)

        #expect(snapshot.area.id == nil)
        #expect(snapshot.area.name == "未分区")
        #expect(manifest.area.id == nil)
        #expect(manifest.area.sourceId == nil)
    }

    @Test("26. Export does not mutate source models")
    func exportDoesNotMutateModels() throws {
        let fixture = makeFixture()
        let originalName = fixture.track.name
        let originalPoints = fixture.track.points.map(\.id)
        let originalArea = fixture.track.area?.id

        _ = try fixture.builder.build(area: fixture.area, exportedAt: 1)

        #expect(fixture.track.name == originalName)
        #expect(fixture.track.points.map(\.id) == originalPoints)
        #expect(fixture.track.area?.id == originalArea)
    }

    @Test("27. Original photos survive staging and cleanup")
    func originalsSurviveCleanup() throws {
        let fixture = makeFixture(includeDefaults: false)
        let item = photo(id: id(1), track: fixture.track, time: 1, created: 1)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]
        fixture.photos.data[item.filePath] = Data([7])
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)

        try withStaging { service, _ in
            let result = try service.stage(snapshot)
            try service.cleanUp(result)
            #expect(fixture.photos.data[item.filePath] == Data([7]))
        }
    }

    @Test("28. Assigned Track is rejected from an unassigned export")
    func assignedTrackRejectedFromUnassignedExport() {
        let fixture = makeFixture(includeDefaults: false)
        fixture.track.area = fixture.area

        #expect(throws: ExportValidationError.trackOutsideArea(trackID: fixture.track.id)) {
            try fixture.builder.buildUnassigned(tracks: [fixture.track], exportedAt: 1)
        }
    }

    @Test("29. Golden export flow contains one Track, one door Tag, and no Wi-Fi")
    func simulatorGoldenExportSnapshot() throws {
        let photos = Phase6PhotoStore()
        let area = Area(name: "导出测试区", createdAt: 1)
        let track = Track(name: "导出测试轨迹", area: area, startedAt: 2, endedAt: 4)
        track.points = [TrackPoint(track: track, timeMs: 3)]
        track.tags = [TrackTag(track: track, timeMs: 3, tagType: .door, note: "导出测试门", createdAt: 3)]
        area.tracks = [track]

        let snapshot = try AreaExportSnapshotBuilder(photoStorage: photos) { _ in true }
            .build(area: area, exportedAt: 5)
        let result = try #require(snapshot.tracks.first)

        #expect(snapshot.tracks.count == 1)
        #expect(result.pointCount == result.points.count)
        #expect(result.tags.first?.note == "导出测试门")
        #expect(result.points.first?.latitude == nil)
        let dto = ExportDTOMapper().track(from: result, areaName: area.name)
        #expect(dto.points.first?.wifiCount == nil)
        #expect(dto.points.first?.wifiTop == nil)
    }

    @Test("30. Phase 6 compatibility fixtures decode with their intended semantics")
    func phase6FixturesDecode() throws {
        let full = try JSONDecoder().decode(
            ExportedTrackDTO.self,
            from: TestFixtures.data(named: "phase6_full_sensor_v2")
        )
        let tags = try JSONDecoder().decode(
            ExportedTrackDTO.self,
            from: TestFixtures.data(named: "phase6_tags_v2")
        )
        let photo = try JSONDecoder().decode(
            ExportedTrackDTO.self,
            from: TestFixtures.data(named: "phase6_photo_v2")
        )
        let unassigned = try JSONDecoder().decode(
            ExportManifestDTO.self,
            from: TestFixtures.data(named: "phase6_unassigned_manifest_v2")
        )
        let multiple = try JSONDecoder().decode(
            ExportManifestDTO.self,
            from: TestFixtures.data(named: "phase6_multiple_manifest_v2")
        )

        #expect(full.points.first?.magneticZ == 3)
        #expect(full.points.first?.wifiCount == nil)
        #expect(tags.tags.first?.createdAt == 1_700_000_201_100)
        #expect(photo.photos.first?.file.hasPrefix("photos/") == true)
        #expect(unassigned.area.sourceId == nil)
        #expect(unassigned.area.name == "未分区")
        #expect(multiple.tracks.map(\.name) == ["Earlier Synthetic Track", "Later Synthetic Track"])
    }

    @Test("31. Unreadable photo produces a typed failure")
    func unreadablePhotoRejected() {
        let fixture = makeFixture(includeDefaults: false)
        let item = photo(id: id(1), track: fixture.track, time: 1, created: 1)
        fixture.track.photos = [item]
        fixture.area.tracks = [fixture.track]
        fixture.photos.unreadablePaths.insert(item.filePath)

        #expect(throws: ExportValidationError.unreadablePhoto(trackID: fixture.track.id, photoID: item.id)) {
            try fixture.builder.build(area: fixture.area, exportedAt: 1)
        }
    }

    @Test("32. DTO point-count mismatch produces a typed failure")
    func pointCountMismatchRejected() throws {
        let fixture = makeFixture()
        let snapshot = try fixture.builder.build(area: fixture.area, exportedAt: 1)
        let track = try #require(snapshot.tracks.first)
        let valid = ExportDTOMapper().track(from: track, areaName: fixture.area.name)
        let invalid = ExportedTrackDTO(
            version: valid.version,
            sourcePlatform: valid.sourcePlatform,
            capabilities: valid.capabilities,
            name: valid.name,
            area: valid.area,
            startedAt: valid.startedAt,
            endedAt: valid.endedAt,
            pointCount: valid.pointCount + 1,
            points: valid.points,
            tags: valid.tags,
            photos: valid.photos
        )

        #expect(throws: ExportValidationError.pointCountMismatch(
            trackID: track.id,
            declared: 3,
            actual: 2
        )) {
            try ExportContractValidator.validate(track: invalid, trackID: track.id)
        }
    }

    private func makeFixture(
        includeDefaults: Bool = true,
        validatesJPEG: Bool = true
    ) -> Phase6Fixture {
        let photos = Phase6PhotoStore()
        let area = Area(id: id(50), name: "Area", createdAt: 1)
        let track = Track(id: id(51), name: "Track", area: area, startedAt: 10, endedAt: 40)
        if includeDefaults {
            track.points = [
                TrackPoint(id: id(2), track: track, timeMs: 30, pressureHpa: 1008),
                TrackPoint(id: id(1), track: track, timeMs: 20, latitude: 22.3, longitude: 114.2),
            ]
            area.tracks = [track]
        }
        return Phase6Fixture(
            area: area,
            track: track,
            photos: photos,
            builder: AreaExportSnapshotBuilder(photoStorage: photos) { _ in validatesJPEG }
        )
    }

    private func tag(id: UUID, track: Track, time: Int64, created: Int64) -> TrackTag {
        TrackTag(id: id, track: track, timeMs: time, tagType: .door, createdAt: created)
    }

    private func photo(id: UUID, track: Track, time: Int64, created: Int64) -> TrackPhoto {
        TrackPhoto(
            id: id,
            track: track,
            timeMs: time,
            filePath: "photos/\(track.id.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg",
            createdAt: created
        )
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomMarkerPhase6-\(UUID().uuidString)", isDirectory: true)
    }

    private func withStaging(_ body: (ExportStagingService, URL) throws -> Void) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ExportStagingService(baseDirectory: root), root)
    }
}

@MainActor
private struct Phase6Fixture {
    let area: Area
    let track: Track
    let photos: Phase6PhotoStore
    let builder: AreaExportSnapshotBuilder
}

private enum Phase6PhotoFailure: Error {
    case unreadable
}

@MainActor
private final class Phase6PhotoStore: PhotoFileStoring {
    var data: [String: Data] = [:]
    var unreadablePaths: Set<String> = []

    func storeJPEG(_ data: Data, trackID: UUID, timeMs: Int64) throws -> String {
        let path = "photos/\(trackID.uuidString.lowercased())/\(timeMs).jpg"
        self.data[path] = data
        return path
    }

    func validate(relativePath: String) throws {
        guard relativePath.hasPrefix("photos/"),
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.split(separator: "/").contains(".."),
              !relativePath.split(separator: "/").contains(".") else {
            throw PhotoStorageError.unsafeRelativePath
        }
    }

    func read(relativePath: String) throws -> Data {
        if unreadablePaths.contains(relativePath) { throw Phase6PhotoFailure.unreadable }
        guard let value = data[relativePath] else { throw PhotoStorageError.missingFile }
        return value
    }

    func delete(relativePath: String) throws { data.removeValue(forKey: relativePath) }
    func deleteTrackDirectory(trackID: UUID) throws {}
}

private final class FailingExportFileSystem: ExportStagingFileSystem {
    private let fileManager = FileManager.default
    private let failOnWrite: Int
    private var writeCount = 0
    private(set) var removeCalls = 0

    init(failOnWrite: Int) { self.failOnWrite = failOnWrite }

    func fileExists(at url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }
    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func write(_ data: Data, to url: URL) throws {
        writeCount += 1
        if writeCount == failOnWrite { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
    func removeItem(at url: URL) throws {
        removeCalls += 1
        try fileManager.removeItem(at: url)
    }
}
