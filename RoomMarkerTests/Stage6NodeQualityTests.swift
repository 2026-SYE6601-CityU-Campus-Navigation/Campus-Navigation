import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Stage 6 offline node quality and form consistency", .serialized)
@MainActor
struct Stage6NodeQualityTests {
    @Test("Quality is frozen at camera return for both node and photo, including zero accuracy")
    func frozenQuality() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.hub.state = live(accuracy: 0, pressure: 1008.25)
        let capture = try capture(f)
        f.hub.state = live(accuracy: 90, pressure: 990)
        let tag = try f.coordinator.saveNode(capture: capture, type: .door, note: "Synthetic", area: nil, floor: "1/F")
        let photo = try NodePhotoAssociation.photo(for: tag)
        #expect(tag.accuracy == 0 && photo.accuracy == 0)
        #expect(tag.pressureHpa == 1008.25 && photo.pressureHpa == 1008.25)
        #expect(tag.timeMs == capture.capturedAt && photo.timeMs == tag.timeMs)
        #expect(try f.photos.read(relativePath: photo.filePath) == capture.jpegData)
    }

    @Test("Unavailable, denied and stale quality remains absent", arguments: ["waiting", "denied", "stale", "unsupported"])
    func absentQuality(_ state: String) throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        var value = live(accuracy: 3, pressure: 1008)
        switch state {
        case "waiting": value = .waiting
        case "denied": value.location = .permissionDenied; value.pressureHpa = .permissionDenied
        case "stale":
            value.location = .stale(.init(value: .init(latitude: 0, longitude: 0, altitude: 12, horizontalAccuracy: 3), capturedAt: .distantPast))
            value.pressureHpa = .stale(.init(value: 1008, capturedAt: .distantPast))
        default: value.location = .unsupported; value.pressureHpa = .unsupported
        }
        f.hub.state = value
        let tag = try f.coordinator.saveNode(capture: capture(f), type: .stairs, note: "", area: nil, floor: "")
        let photo = try NodePhotoAssociation.photo(for: tag)
        #expect(tag.accuracy == nil && tag.pressureHpa == nil)
        #expect(photo.accuracy == nil && photo.pressureHpa == nil)
    }

    @Test("Invalid live values are absent, not zero-filled", arguments: [-1.0, Double.nan, Double.infinity])
    func invalidLive(_ value: Double) {
        let metadata = TrackCaptureMetadataAssembler().assemble(from: live(accuracy: value, pressure: value))
        #expect(metadata.accuracy == nil && metadata.pressureHpa == nil)
        #expect(metadata.hasValidQuality)
        #expect(TrackCaptureMetadataAssembler().assemble(from: live(accuracy: 0, pressure: 0)).pressureHpa == nil)
    }

    @Test("Location denial does not discard independently available pressure")
    func pressureIndependent() {
        var state = live(accuracy: 3, pressure: 1008)
        state.location = .permissionDenied
        state.permission = .denied
        let metadata = TrackCaptureMetadataAssembler().assemble(from: state)
        #expect(metadata.latitude == nil && metadata.accuracy == nil && metadata.pressureHpa == 1008)
    }

    @Test("A to B selection survives camera success, cancellation, retake and immutable Save snapshot")
    func cameraRoundtrip() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let (a, b) = try areas(f)
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: a, floor: "1/F"))
        form.selectedAreaID = b.id
        form.selectedType = .door
        form.floor = " 2/F "
        form.note = "Synthetic B"
        f.hub.state = live(accuracy: 4, pressure: 1002)
        try form.receive(capture(f))
        let firstCapture = form.capture
        try form.receive(f.coordinator.freezePhotoCapture(.cancelled))
        #expect(form.capture == firstCapture && form.selectedAreaID == b.id && form.floor == " 2/F ")
        f.hub.state = live(accuracy: 5, pressure: 1001)
        try form.receive(capture(f))
        #expect(form.capture?.id != firstCapture?.id && form.selectedAreaID == b.id)
        let request = try form.request(availableAreaIDs: [a.id, b.id], isNode: true)
        // Later changes cannot mutate the values already selected by Save.
        form.selectedAreaID = a.id
        form.floor = "9/F"
        form.note = "Later edit"
        f.hub.state = .waiting
        let node = try save(request, with: f)
        let photo = try NodePhotoAssociation.photo(for: node)
        #expect(node.areaID == b.id && node.floor == "2/F" && node.note == "Synthetic B")
        #expect(node.accuracy == 5 && photo.accuracy == 5 && node.pressureHpa == 1001 && photo.pressureHpa == 1001)
        #expect(node.id == request.capture.id && f.track.tags.count == 1 && f.track.photos.count == 1)
        let nextForm = NodeCaptureForm(trackID: f.track.id, initialLocation: f.coordinator.tagLocationContext)
        #expect(nextForm.selectedAreaID == b.id && nextForm.floor == "2/F" && nextForm.capture == nil)
    }

    @Test("Empty/transient area results do not silently clear selection or fall back to A")
    func transientAreaResults() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let (a, b) = try areas(f)
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: a))
        form.selectedAreaID = b.id
        try form.receive(capture(f))
        #expect(throws: NodeCaptureError.areaUnavailable) { try form.request(availableAreaIDs: [], isNode: true) }
        #expect(throws: NodeCaptureError.areaUnavailable) { try form.request(availableAreaIDs: [a.id], isNode: true) }
        #expect(form.selectedAreaID == b.id)
        #expect(try form.request(availableAreaIDs: [b.id, a.id], isNode: true).location.areaID == b.id)
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
        form.selectedAreaID = nil // Only explicit user selection means unassigned.
        let node = try save(form.request(availableAreaIDs: [], isNode: true), with: f)
        #expect(node.areaID == nil && node.areaStateRawValue == "unassigned")
    }

    @Test("Area deleted after Save snapshot fails without orphan photo or silent reassignment")
    func deletedArea() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let (a, b) = try areas(f)
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: b))
        try form.receive(capture(f))
        let request = try form.request(availableAreaIDs: [a.id, b.id], isNode: true)
        try Phase2DataStore(context: f.context).deleteAreaPreservingContents(b)
        #expect(throws: NodeCaptureError.areaUnavailable) { try save(request, with: f) }
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty && f.coordinator.mediaCleanupMessage == nil)
        let enumerator = try #require(FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: nil))
        #expect(enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jpg" }.isEmpty)
        #expect(form.selectedAreaID == request.location.areaID)
    }

    @Test("Failed save preserves B, frozen quality and original JPEG for one successful retry")
    func retrySelection() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let (a, b) = try areas(f)
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: a))
        form.selectedAreaID = b.id
        f.hub.state = live(accuracy: 4.5, pressure: 1007.8)
        try form.receive(capture(f))
        let request = try form.request(availableAreaIDs: [a.id, b.id], isNode: true)
        f.failure.enabled = true
        #expect(throws: Stage4Failure.save) { try save(request, with: f) }
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty && !f.context.hasChanges)
        #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
        #expect(form.selectedAreaID == b.id && form.capture == request.capture)
        f.failure.enabled = false
        f.hub.state = .waiting
        let node = try save(form.request(availableAreaIDs: [a.id, b.id], isNode: true), with: f)
        let photo = try NodePhotoAssociation.photo(for: node)
        #expect(node.areaID == b.id && node.accuracy == 4.5 && photo.pressureHpa == 1007.8)
        #expect(try f.photos.read(relativePath: photo.filePath) == request.capture.jpegData)
        #expect(throws: NodeCaptureError.alreadySaved) { try save(request, with: f) }
        #expect(f.track.tags.count == 1 && f.track.photos.count == 1)
    }

    @Test("Late camera result from a later session cannot attach to the original form")
    func sessionSwitch() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: nil))
        try await f.coordinator.stop()
        try f.coordinator.start(name: "Later")
        #expect(throws: NodeCaptureError.changedSession) { try form.receive(capture(f)) }
        #expect(form.capture == nil && f.coordinator.activeTrack?.photos.isEmpty == true)
        try await f.coordinator.stop()
    }

    @Test("Editing location preserves quality, photo metadata, bytes and original capture time")
    func editPreservation() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let (a, b) = try areas(f)
        f.hub.state = live(accuracy: 3.25, pressure: 1006.5)
        let node = try f.coordinator.saveNode(capture: capture(f), type: .door, note: "Synthetic", area: a, floor: "1/F")
        let photo = try NodePhotoAssociation.photo(for: node)
        let photoID = photo.id, path = photo.filePath, time = node.timeMs
        try Phase2DataStore(context: f.context).updateTagLocation(node, area: b, floor: "2/F")
        #expect(node.areaID == b.id && node.floor == "2/F" && node.accuracy == 3.25 && node.pressureHpa == 1006.5)
        #expect(photo.id == photoID && photo.filePath == path && photo.tagID == node.id)
        #expect(photo.accuracy == 3.25 && photo.pressureHpa == 1006.5 && node.timeMs == time && photo.timeMs == time)
        #expect(try f.photos.read(relativePath: path) == f.jpeg)
    }

    @Test("New quality fields survive ZIP; absent historical v3 keys remain nil")
    func exportCompatibility() async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let originals = try f.originalPhotos()
        let snapshot = try f.snapshot()
        let archive = try f.archive.createArchive(from: f.staging.stage(snapshot), areaName: "Synthetic", exportedAt: 70000)
        let entries = try Stage5ZIP.read(archive.archiveURL)
        let dto = try JSONDecoder().decode(ExportV3Track.self, from: #require(entries["tracks/\(f.id).json"]))
        for node in dto.tags where node.recordKind == "node" {
            let photo = try #require(dto.photos.first { $0.tagId == node.id })
            #expect(node.accuracy == 3 && node.pressureHpa == 1008)
            #expect(photo.accuracy == node.accuracy && photo.pressureHpa == node.pressureHpa)
            #expect(entries[photo.file] == originals[photo.file])
        }
        #expect(dto.photos.first { $0.kind == "scenery" }?.pressureHpa == 1008)
        #expect(dto.tags.first { $0.recordKind == "legacy" }?.accuracy == nil)
        let old = try JSONDecoder().decode(ExportV3Track.self, from: TestFixtures.data(named: "stage5_legacy_track_v3"))
        #expect(old.tags.allSatisfy { $0.accuracy == nil && $0.pressureHpa == nil })
        #expect(try f.originalPhotos() == originals && !f.base.context.hasChanges)
    }

    @Test("Export rejects invalid or inconsistent node/photo quality", arguments: ["negative", "zeroPressure", "nonfinite", "mismatch"])
    func exportValidation(_ defect: String) async throws {
        let f = try await Stage5Fixture()
        defer { f.dispose() }
        let node = try #require(f.base.track.tags.first { $0.isNode })
        switch defect {
        case "negative": node.accuracy = -1
        case "zeroPressure": node.pressureHpa = 0
        case "nonfinite": node.pressureHpa = .infinity
        default: node.accuracy = 7
        }
        try f.base.context.save()
        #expect(throws: (any Error).self) { try f.snapshot() }
        #expect(!f.base.context.hasChanges && f.base.track.photos.count == 4)
    }

    @Test("V2 gate cannot silently drop new quality on historical standalone records", arguments: [false, true])
    func legacyExportGate(_ photoQuality: Bool) throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let old = Track(name: "Synthetic old", startedAt: 1, endedAt: 3)
        f.context.insert(old)
        if photoQuality {
            f.context.insert(TrackPhoto(track: old, timeMs: 2, filePath: "unused.jpg", pressureHpa: 1008, createdAt: 2))
        } else {
            f.context.insert(TrackTag(track: old, timeMs: 2, tagType: .door, accuracy: 3, createdAt: 2))
        }
        try f.context.save()
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: f.photos).buildUnassigned(tracks: [old], exportedAt: 4)
        }
    }

    @Test("Malformed supplied quality fails before file creation", arguments: ["accuracy", "pressure", "infinity"])
    func invalidSuppliedQuality(_ field: String) throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let metadata = TrackCaptureMetadata(latitude: nil, longitude: nil, altitude: nil, headingDeg: nil,
            accuracy: field == "accuracy" ? -1 : nil, pressureHpa: field == "infinity" ? .infinity : (field == "pressure" ? 0 : nil))
        let capture = CapturedTrackPhoto(id: UUID(), trackID: f.track.id, jpegData: f.jpeg, capturedAt: 1600, metadata: metadata)
        #expect(throws: NodeCaptureError.invalidSensorMetadata) {
            try f.coordinator.saveNode(capture: capture, type: .door, note: "", area: nil, floor: "")
        }
        #expect(throws: NodeCaptureError.invalidSensorMetadata) { try f.coordinator.saveScenery(capture: capture, note: "") }
        #expect(f.track.photos.isEmpty && f.track.tags.isEmpty)
        let enumerator = try #require(FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: nil))
        #expect(enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jpg" }.isEmpty)
    }

    private func capture(_ f: Stage4Fixture) throws -> CapturedTrackPhoto {
        try #require(try f.coordinator.freezePhotoCapture(.success(jpegData: f.jpeg, capturedAt: 1600)))
    }
    private func save(_ request: NodeCaptureRequest, with f: Stage4Fixture) throws -> TrackTag {
        try f.coordinator.saveNode(capture: request.capture, type: request.type, note: request.note, location: request.location)
    }
    private func areas(_ f: Stage4Fixture) throws -> (Area, Area) {
        let a = Area(name: "Synthetic A", createdAt: 1), b = Area(name: "Synthetic B", createdAt: 2)
        f.context.insert(a); f.context.insert(b)
        try f.context.save()
        return (a, b)
    }
    private func live(accuracy: Double, pressure: Double) -> LiveSensorState {
        .init(permission: .authorizedWhenInUse,
              location: .available(.init(value: .init(latitude: 0, longitude: 0, altitude: 12, horizontalAccuracy: accuracy), capturedAt: Date())),
              pressureHpa: .available(.init(value: pressure, capturedAt: Date())),
              magneticField: .unavailable, headingDeg: .available(.init(value: 90, capturedAt: Date())))
    }
}
