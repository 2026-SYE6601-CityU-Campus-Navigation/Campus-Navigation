import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 1 tag-based Area index and transitional v2 export")
@MainActor
struct Stage1AreaIndexExportTests {
    @Test("One global Track with A/A/B tags appears once in each Area")
    func distinctTracksAcrossAreas() {
        let areaA = Area(name: "A", createdAt: 1)
        let areaB = Area(name: "B", createdAt: 1)
        let track = Track(name: "Cross-building", startedAt: 2, isGlobalRecording: true)
        track.tags = [
            tag(track, areaID: areaA.id, state: "assigned"),
            tag(track, areaID: areaA.id, state: "assigned"),
            tag(track, areaID: areaB.id, state: "assigned"),
        ]

        #expect(TrackAreaIndex.tracks(in: areaA.id, from: [track, track]).map(\.id) == [track.id])
        #expect(TrackAreaIndex.tracks(in: areaB.id, from: [track, track]).map(\.id) == [track.id])
        #expect(TrackAreaIndex.unassigned(in: [track]).isEmpty)
        #expect(track.area == nil)
        #expect(track.tags.count == 3)
    }

    @Test("Tracks without tags or with unknown tags are not unassigned")
    func unknownDoesNotMeanUnassigned() {
        let area = Area(name: "A", createdAt: 1)
        let empty = Track(name: "No tags", startedAt: 2, isGlobalRecording: true)
        let unknown = Track(name: "Unknown", startedAt: 3, isGlobalRecording: true)
        unknown.tags = [tag(unknown), tag(unknown, areaID: area.id)]

        #expect(TrackAreaIndex.unassigned(in: [empty, unknown]).isEmpty)
        #expect(TrackAreaIndex.tracks(in: area.id, from: [empty, unknown]).isEmpty)
        #expect(TrackAreaIndex.areaLabel(for: unknown.tags[0], areas: [area]) == "区域未知（历史标签）")
    }

    @Test("Only explicit unassigned tags with no Area ID establish unassigned membership")
    func explicitUnassignedMembership() {
        let area = Area(name: "A", createdAt: 1)
        let track = Track(name: "Explicit", startedAt: 2, isGlobalRecording: true)
        track.tags = [tag(track, state: "unassigned"), tag(track, state: "unassigned")]
        let inconsistent = Track(name: "Inconsistent", startedAt: 3, isGlobalRecording: true)
        inconsistent.tags = [tag(inconsistent, areaID: area.id, state: "unassigned")]

        #expect(TrackAreaIndex.unassigned(in: [track, inconsistent, track]).map(\.id) == [track.id])
        #expect(TrackAreaIndex.tracks(in: area.id, from: [track, inconsistent]).isEmpty)
        #expect(TrackAreaIndex.areaLabel(for: track.tags[0], areas: [area]) == "未分区")
    }

    @Test("Same-name Areas remain distinct by UUID")
    func sameNameAreasDoNotMerge() {
        let first = Area(name: "Same name", createdAt: 1)
        let second = Area(name: "Same name", createdAt: 1)
        let firstTrack = Track(name: "First", startedAt: 2, isGlobalRecording: true)
        let secondTrack = Track(name: "Second", startedAt: 3, isGlobalRecording: true)
        firstTrack.tags = [tag(firstTrack, areaID: first.id, state: "assigned")]
        secondTrack.tags = [tag(secondTrack, areaID: second.id, state: "assigned")]
        let tracks = [secondTrack, firstTrack]

        #expect(first.id != second.id)
        #expect(TrackAreaIndex.tracks(in: first.id, from: tracks).map(\.id) == [firstTrack.id])
        #expect(TrackAreaIndex.tracks(in: second.id, from: tracks).map(\.id) == [secondTrack.id])
        #expect(TrackAreaIndex.areaLabel(for: firstTrack.tags[0], areas: [second]) == "区域已不可用")
    }

    @Test("Legacy Track.area is provenance rather than current membership")
    func legacyAreaDoesNotInferCurrentMembership() {
        let area = Area(name: "Historical", createdAt: 1)
        let track = Track(name: "Legacy", area: area, startedAt: 2, legacyAreaName: area.name)
        track.tags = [tag(track)]
        area.tracks = [track]

        #expect(TrackAreaIndex.tracks(in: area.id, from: [track]).isEmpty)
        #expect(TrackAreaIndex.unassigned(in: [track]).isEmpty)
        #expect(track.area?.id == area.id)
        #expect(track.legacyAreaName == "Historical")
    }

    @Test("Area allTracks prevents a partial legacy-only v2 export when a global member exists")
    func mixedAreaExportRejectsInsteadOfOmittingGlobalTrack() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let area = Area(name: "A", createdAt: 1)
        let legacy = Track(name: "Legacy", area: area, startedAt: 2)
        let global = Track(name: "Global", startedAt: 3, isGlobalRecording: true)
        global.tags = [tag(global, areaID: area.id, state: "assigned")]
        area.tracks = [legacy]

        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: storage)
                .build(area: area, exportedAt: 4, allTracks: [legacy, global])
        }
        #expect(area.tracks.map(\.id) == [legacy.id])
        #expect(global.area == nil)
        #expect(global.tags.count == 1)
    }

    @Test("Area allTracks finds global members even when area.tracks is empty")
    func areaExportFindsGlobalTrackOutsideLegacyRelationship() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let area = Area(name: "A", createdAt: 1)
        let global = Track(name: "Global", startedAt: 2, isGlobalRecording: true)
        global.tags = [tag(global, areaID: area.id, state: "assigned")]

        #expect(area.tracks.isEmpty)
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: storage)
                .build(area: area, exportedAt: 3, allTracks: [global])
        }
    }

    @Test("Persisted Area export without allTracks still discovers global tag membership")
    func persistedAreaExportCannotSilentlyOmitGlobalMembers() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Persisted Area", createdAt: 1)
        let global = Track(name: "Persisted global", startedAt: 2, isGlobalRecording: true)
        let assignedTag = tag(global, areaID: area.id, state: "assigned")
        context.insert(area)
        context.insert(global)
        context.insert(assignedTag)
        try context.save()

        let readContext = ModelContext(container)
        let persistedArea = try #require(try readContext.fetch(FetchDescriptor<Area>()).first)
        let persistedTrack = try #require(try readContext.fetch(FetchDescriptor<Track>()).first)
        #expect(persistedArea.tracks.isEmpty)
        #expect(persistedTrack.area == nil)
        #expect(persistedTrack.isGlobalRecording)
        #expect(persistedTrack.tags.first?.areaID == persistedArea.id)
        #expect(persistedTrack.tags.first?.areaStateRawValue == "assigned")
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: storage)
                .build(area: persistedArea, exportedAt: 3)
        }
    }

    @Test("Direct unassigned export rejects global recordings even before their first tag")
    func directGlobalUnassignedExportRejected() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let global = Track(name: "Global without tags", startedAt: 1, isGlobalRecording: true)

        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: storage)
                .buildUnassigned(tracks: [global], exportedAt: 2)
        }
    }

    @Test("Legacy recordings with any new tag ownership or floor metadata require v3")
    func richLegacyMetadataCannotBeSilentlyDropped() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let builder = AreaExportSnapshotBuilder(photoStorage: storage)
        let area = Area(name: "A", createdAt: 1)
        let cases: [(state: String, areaID: UUID?, floor: String)] = [
            ("assigned", area.id, ""),
            ("unassigned", nil, ""),
            ("unknown", area.id, ""),
            ("unknown", nil, "2F"),
        ]
        for metadata in cases {
            let legacy = Track(name: "Edited legacy", area: area, startedAt: 2)
            legacy.tags = [tag(
                legacy,
                areaID: metadata.areaID,
                state: metadata.state,
                floor: metadata.floor
            )]
            area.tracks = [legacy]
            #expect(throws: ExportValidationError.requiresV3Export) {
                try builder.build(area: area, exportedAt: 3, allTracks: [legacy])
            }
        }
    }

    @Test("Unassigned v2 candidates include edited legacy members despite historical Track.area")
    func unassignedCandidatesDoNotOmitEditedLegacyTrack() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let area = Area(name: "Historical", createdAt: 1)
        let edited = Track(name: "Edited legacy", area: area, startedAt: 2)
        edited.tags = [tag(edited, state: "unassigned")]
        let plain = Track(name: "Old unassigned", startedAt: 3)
        let unknownGlobal = Track(name: "Unknown global", startedAt: 4, isGlobalRecording: true)
        let candidates = TrackAreaIndex.unassignedV2ExportCandidates(
            in: [edited, plain, edited, unknownGlobal]
        )

        #expect(Set(candidates.map(\.id)) == Set([plain.id, edited.id]))
        #expect(candidates.count == 2)
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: storage)
                .buildUnassigned(tracks: candidates, exportedAt: 5)
        }
        #expect(edited.area?.id == area.id)
        #expect(edited.tags[0].areaStateRawValue == "unassigned")
    }

    @Test("Pure legacy data still exports v2 without changing source models or owned JPEG")
    func pureLegacyV2ExportRemainsCompatibleAndReadOnly() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let area = Area(name: "Legacy Area", createdAt: 1)
        let track = Track(name: "Legacy", area: area, startedAt: 2, endedAt: 5)
        let earlier = TrackPoint(track: track, timeMs: 2, pressureHpa: 1_010)
        let later = TrackPoint(track: track, timeMs: 4, headingDeg: 90)
        track.points = [later, earlier]
        track.tags = [tag(track)]
        let jpeg = jpegFixture()
        let path = try storage.storeJPEG(jpeg, trackID: track.id, timeMs: 3)
        let photo = TrackPhoto(track: track, timeMs: 3, filePath: path, note: "Fixture", createdAt: 3)
        track.photos = [photo]
        area.tracks = [track]
        let originalPointIDs = track.points.map(\.id)
        let builder = AreaExportSnapshotBuilder(photoStorage: storage)
        let snapshot = try builder.build(area: area, exportedAt: 6, allTracks: [track])
        let staging = try ExportStagingService(baseDirectory: root.appendingPathComponent("stage"))
            .stage(snapshot)
        let trackURL = try #require(staging.trackURLs.first)
        let data = try Data(contentsOf: trackURL)
        let exported = try JSONDecoder().decode(ExportedTrackDTO.self, from: data)
        let manifest = try JSONDecoder().decode(
            ExportManifestDTO.self,
            from: Data(contentsOf: staging.manifestURL)
        )
        let archive = try StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("archives"))
            .createArchive(from: staging, areaName: area.name, exportedAt: 6)

        #expect(exported.version == 2)
        #expect(exported.area == area.name)
        #expect(exported.sourcePlatform == "ios")
        #expect(exported.capabilities?.nearbyWifiFingerprint == .unsupported)
        #expect(exported.points.map(\.timeMs) == [2, 4])
        #expect(exported.pointCount == 2)
        #expect(exported.tags.count == 1)
        #expect(exported.photos.map(\.file) == [path])
        #expect(manifest.version == 2)
        #expect(manifest.trackCount == 1)
        #expect(manifest.tracks.first?.pointCount == 2)
        #expect(manifest.tracks.first?.file == snapshot.tracks.first?.fileName)
        #expect(FileManager.default.fileExists(atPath: archive.archiveURL.path))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tags = try #require(object["tags"] as? [[String: Any]])
        #expect(object["isGlobalRecording"] == nil)
        #expect(tags.first?["areaID"] == nil)
        #expect(tags.first?["areaState"] == nil)
        #expect(tags.first?["floor"] == nil)
        #expect(try storage.read(relativePath: path) == jpeg)
        #expect(track.points.map(\.id) == originalPointIDs)
        #expect(track.area?.id == area.id)
        #expect(track.isGlobalRecording == false)
        #expect(track.legacyAreaName == nil)
        #expect(track.tags[0].areaID == nil)
        #expect(track.tags[0].areaStateRawValue == "unknown")
        #expect(track.tags[0].floor.isEmpty)
        #expect(photo.filePath == path)
        #expect(try builder.build(area: area, exportedAt: 6, allTracks: [track]) == snapshot)
    }

    @Test("Legacy export snapshot remains a value after later source edits")
    func legacySnapshotIsImmutable() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let area = Area(name: "Original Area", createdAt: 1)
        let track = Track(name: "Original Track", area: area, startedAt: 2, endedAt: 4)
        let point = TrackPoint(track: track, timeMs: 3, headingDeg: 45)
        let originalTag = tag(track)
        track.points = [point]
        track.tags = [originalTag]
        area.tracks = [track]
        let snapshot = try AreaExportSnapshotBuilder(photoStorage: storage)
            .build(area: area, exportedAt: 5, allTracks: [track])

        area.name = "Changed Area"
        track.name = "Changed Track"
        track.isGlobalRecording = true
        point.headingDeg = 180
        originalTag.note = "Changed note"
        originalTag.areaID = area.id
        originalTag.areaStateRawValue = "assigned"
        originalTag.floor = "3F"
        track.points = []

        #expect(snapshot.area.name == "Original Area")
        #expect(snapshot.tracks.first?.name == "Original Track")
        #expect(snapshot.tracks.first?.pointCount == 1)
        #expect(snapshot.tracks.first?.points.first?.headingDeg == 45)
        #expect(snapshot.tracks.first?.tags.first?.note == "Fixture tag")
    }

    @Test("Area coordinator rejects mixed legacy/global data before staging or ZIP creation")
    func coordinatorRejectsAreaExportWithoutArtifacts() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let area = Area(name: "A", createdAt: 1)
        let legacy = Track(name: "Legacy", area: area, startedAt: 2)
        let global = Track(name: "Global", startedAt: 3, isGlobalRecording: true)
        global.tags = [tag(global, areaID: area.id, state: "assigned")]
        global.points = [TrackPoint(track: global, timeMs: 3)]
        let jpeg = jpegFixture()
        let path = try storage.storeJPEG(jpeg, trackID: global.id, timeMs: 3)
        global.photos = [TrackPhoto(track: global, timeMs: 3, filePath: path, createdAt: 3)]
        area.tracks = [legacy]
        let coordinator = makeCoordinator(storage: storage, root: root)

        try coordinator.start(area: area, allTracks: [legacy, global])
        await coordinator.waitForCurrentExport()

        expectV3Rejection(coordinator, root: root)
        #expect(try storage.read(relativePath: path) == jpeg)
        #expect(global.points.count == 1)
        #expect(global.tags.count == 1)
        #expect(global.photos.count == 1)
        #expect(global.photos.first?.filePath == path)
        #expect(global.area == nil)
        #expect(area.tracks.map(\.id) == [legacy.id])
    }

    @Test("Unassigned coordinator rejects global data before staging or ZIP creation")
    func coordinatorRejectsUnassignedExportWithoutArtifacts() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try LocalPhotoFileStore(rootURL: root.appendingPathComponent("source"))
        let global = Track(name: "Global", startedAt: 1, isGlobalRecording: true)
        global.tags = [tag(global, state: "unassigned")]
        let coordinator = makeCoordinator(storage: storage, root: root)

        try coordinator.startUnassigned(tracks: [global])
        await coordinator.waitForCurrentExport()

        expectV3Rejection(coordinator, root: root)
        #expect(global.isGlobalRecording)
        #expect(global.area == nil)
        #expect(global.tags[0].areaStateRawValue == "unassigned")
    }

    private func tag(
        _ track: Track,
        areaID: UUID? = nil,
        state: String = "unknown",
        floor: String = ""
    ) -> TrackTag {
        TrackTag(
            track: track,
            timeMs: track.startedAt,
            tagType: .door,
            note: "Fixture tag",
            createdAt: track.startedAt,
            areaID: areaID,
            areaStateRawValue: state,
            floor: floor
        )
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Stage1AreaIndexExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func jpegFixture() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
    }

    private func makeCoordinator(storage: LocalPhotoFileStore, root: URL) -> AreaExportCoordinator {
        AreaExportCoordinator(
            photoStorage: storage,
            stagingService: ExportStagingService(baseDirectory: root.appendingPathComponent("stage")),
            archiveService: StoredZIPArchiveService(archiveDirectory: root.appendingPathComponent("archives")),
            nowMilliseconds: { 10 }
        )
    }

    private func expectV3Rejection(_ coordinator: AreaExportCoordinator, root: URL) {
        let failure = ExportErrorPresenter.failure(for: ExportValidationError.requiresV3Export)
        #expect(coordinator.state == .failed(failure))
        #expect(coordinator.stateHistory == [.idle, .preparingSnapshot, .failed(failure)])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("stage").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("archives").path))
    }
}
