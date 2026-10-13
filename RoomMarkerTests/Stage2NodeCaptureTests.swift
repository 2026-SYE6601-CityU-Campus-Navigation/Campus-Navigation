import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 2 node capture", .serialized)
@MainActor
struct Stage2NodeCaptureTests {
    @Test("All eleven types save exactly one same-Track node photo", arguments: TrackTagType.allCases)
    func types(_ type: TrackTagType) throws {
        try withFixture { (f: Stage2Fixture) throws in
            let tag = try f.save(type: type)
            let photo = try NodePhotoAssociation.photo(for: tag)
            #expect(tag.isNode && photo.isNodePhoto)
            #expect(tag.tagType == type)
            #expect(photo.tagID == tag.id)
            #expect(photo.track?.id == f.track.id)
            #expect(f.track.tags.count == 1 && f.track.photos.count == 1)
            #expect(try f.files.read(relativePath: photo.filePath) == f.jpeg)
            #expect(f.coordinator.isRecording && f.ticker.starts == 1)
        }
    }

    @Test("Original six raw values are unchanged, five additions are unique")
    func typeContract() {
        #expect(TrackTagType.allCases.count == 11)
        #expect(Set(TrackTagType.allCases.map(\.rawValue)).count == 11)
        #expect(TrackTagType.gate.rawValue == "门禁")
        #expect(TrackTagType.mainGate.rawValue == "大门")
    }

    @Test("Denied/restricted camera does not re-prompt or create records")
    func deniedCamera() async throws {
        let f = try Stage2Fixture()
        defer { f.dispose() }
        for state in [CameraAuthorizationState.denied, .restricted] {
            let camera = Stage2Camera(state: state)
            do {
                try await NodeCameraAccess.authorize(camera)
                Issue.record("Expected unavailable camera permission")
            } catch {}
            #expect(camera.requests == 0)
        }
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
    }

    @Test("Undetermined camera permission is requested only once")
    func cameraAuthorizationOnce() async throws {
        let camera = Stage2Camera(state: .notDetermined)
        try await NodeCameraAccess.authorize(camera)
        try await NodeCameraAccess.authorize(camera)
        #expect(camera.requests == 1)
    }

    @Test("Authorized but unavailable hardware never enters capture")
    func unavailableCamera() async {
        let camera = Stage2Camera(state: .authorized)
        camera.isCameraAvailable = false
        do {
            try await NodeCameraAccess.authorize(camera)
            Issue.record("Expected absent camera")
        } catch {}
        #expect(camera.requests == 0)
    }

    @Test("Decodable non-JPEG image is not accepted as node JPEG")
    func pngRejected() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let image = try #require(UIImage(data: f.jpeg))
            let png = try #require(image.pngData())
            #expect(throws: NodeCaptureError.invalidImage) {
                try f.coordinator.freezePhotoCapture(.success(jpegData: png, capturedAt: 2000))
            }
        }
    }

    @Test("Node paths reject traversal, absolute paths and another Track directory")
    func ownedNodePaths() {
        let id = UUID()
        let prefix = "photos/\(id.uuidString.lowercased())"
        #expect(NodePhotoAssociation.isOwnedFilePath(prefix + "/safe.jpg", trackID: id))
        #expect(!NodePhotoAssociation.isOwnedFilePath(prefix + "/../escape.jpg", trackID: id))
        #expect(!NodePhotoAssociation.isOwnedFilePath("/" + prefix + "/safe.jpg", trackID: id))
        #expect(!NodePhotoAssociation.isOwnedFilePath("photos/\(UUID())/safe.jpg", trackID: id))
        #expect(!NodePhotoAssociation.isOwnedFilePath(prefix + "/dir/safe.jpg", trackID: id))
    }

    @Test("Cancel and unavailable create no node, photo or owned JPEG")
    func cancellation() throws {
        try withFixture { (f: Stage2Fixture) throws in
            #expect(try f.coordinator.freezePhotoCapture(.cancelled) == nil)
            #expect(try f.coordinator.freezePhotoCapture(.unavailable) == nil)
            #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
            #expect(try f.jpegFiles().isEmpty)
        }
    }

    @Test("Camera failure creates no metadata")
    func cameraFailure() throws {
        try withFixture { (f: Stage2Fixture) throws in
            #expect(throws: TrackMediaError.captureFailed("synthetic")) {
                try f.coordinator.freezePhotoCapture(.failed("synthetic"))
            }
            #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
        }
    }

    @Test("Empty and corrupt images are rejected before file write")
    func badImages() throws {
        try withFixture { (f: Stage2Fixture) throws in
            #expect(throws: TrackMediaError.emptyImageData) {
                try f.coordinator.freezePhotoCapture(.success(jpegData: Data(), capturedAt: 2000))
            }
            #expect(throws: NodeCaptureError.invalidImage) {
                try f.coordinator.freezePhotoCapture(.success(jpegData: Data("bad".utf8), capturedAt: 2000))
            }
            #expect(try f.jpegFiles().isEmpty)
            #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
        }
    }

    @Test("File failure creates neither half of the node")
    func fileFailure() throws {
        try withFixture { (f: Stage2Fixture) throws in
            f.files.failWrites = true
            #expect(throws: Stage2Failure.file) { try f.save() }
            #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
            #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
            #expect(try f.jpegFiles().isEmpty)
        }
    }

    @Test("Database save failure rolls back both records and compensates JPEG")
    func databaseFailure() throws {
        try withFixture { (f: Stage2Fixture) throws in
            f.failure.save = true
            #expect(throws: Stage2Failure.database) { try f.save() }
            #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
            #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
            #expect(try f.jpegFiles().isEmpty)
            #expect(f.coordinator.isRecording)
        }
    }

    @Test("Compensation failure is visible and retry removes only orphan JPEG")
    func compensationRetry() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let preserved = try f.coordinator.saveScenery(capture: f.capture(), note: "keep")
            let path = preserved.filePath
            f.failure.save = true
            f.files.failDeletes = true
            #expect(throws: NodeCaptureError.compensationPending) { try f.save() }
            #expect(f.coordinator.mediaCleanupMessage != nil)
            #expect(try f.jpegFiles().count == 2)
            #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
            f.files.failDeletes = false
            f.coordinator.retryPhotoCleanup(protecting: [path])
            #expect(f.coordinator.mediaCleanupMessage == nil)
            #expect(try f.jpegFiles().count == 1)
            #expect(try f.files.read(relativePath: path) == f.jpeg)
        }
    }

    @Test("A failed node can retry the same frozen capture without duplicate metadata")
    func saveRetry() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let capture = try f.capture()
            f.failure.save = true
            #expect(throws: Stage2Failure.database) {
                try f.coordinator.saveNode(capture: capture, type: .door, note: "", area: nil, floor: "")
            }
            f.failure.save = false
            let tag = try f.coordinator.saveNode(capture: capture, type: .door, note: "", area: nil, floor: "")
            #expect(tag.id == capture.id)
            #expect(f.track.tags.count == 1 && f.track.photos.count == 1)
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Repeated confirmation is rejected before creating another file")
    func duplicateConfirmation() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let capture = try f.capture()
            _ = try f.coordinator.saveNode(capture: capture, type: .door, note: "", area: nil, floor: "")
            #expect(throws: NodeCaptureError.alreadySaved) {
                try f.coordinator.saveNode(capture: capture, type: .door, note: "", area: nil, floor: "")
            }
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Camera metadata and time stay frozen while the form remains open")
    func frozenMetadata() throws {
        try withFixture { (f: Stage2Fixture) throws in
            f.hub.state = state(heading: 42)
            let capture = try f.capture()
            f.hub.state = state(heading: 99)
            let tag = try f.coordinator.saveNode(capture: capture, type: .stairs, note: "  note  ", area: nil, floor: " B1 ")
            let photo = try NodePhotoAssociation.photo(for: tag)
            #expect(tag.headingDeg == 42 && photo.headingDeg == 42)
            #expect(tag.timeMs == 2000 && photo.timeMs == 2000)
            #expect(tag.note == "note" && tag.floor == "B1")
            #expect(tag.latitude == nil && photo.longitude == nil)
        }
    }

    @Test("Saved node location seeds the next capture, including explicit empty floor")
    func locationInheritance() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let a = Area(name: "Synthetic A", createdAt: 1)
            f.context.insert(a)
            try f.context.save()
            _ = try f.coordinator.saveNode(capture: f.capture(), type: .stairs, note: "", area: a, floor: "2/F")
            #expect(f.coordinator.tagLocationContext == TagLocationContext(area: a, floor: "2/F"))
            _ = try f.save()
            #expect(f.coordinator.tagLocationContext == TagLocationContext(area: nil))
        }
    }

    @Test("Scenery stays independent and uses frozen metadata")
    func scenery() throws {
        try withFixture { (f: Stage2Fixture) throws in
            f.hub.state = state(heading: 10)
            let capture = try f.capture()
            f.hub.state = .waiting
            let photo = try f.coordinator.saveScenery(capture: capture, note: "view")
            #expect(photo.kindRawValue == "scenery" && photo.tagID == nil)
            #expect(photo.headingDeg == 10)
            #expect(f.track.tags.isEmpty)
        }
    }

    @Test("Node capture without active recording is rejected")
    func inactive() async throws {
        let f = try Stage2Fixture()
        defer { f.dispose() }
        try await f.coordinator.stop()
        #expect(throws: TrackMediaError.noActiveTrack) { try f.capture() }
    }

    @Test("A capture cannot be attached to a later recording session")
    func changedSession() async throws {
        let f = try Stage2Fixture()
        defer { f.dispose() }
        let capture = try f.capture()
        try await f.coordinator.stop()
        try f.coordinator.start(name: "Later")
        #expect(throws: NodeCaptureError.changedSession) {
            try f.coordinator.saveNode(capture: capture, type: .door, note: "", area: nil, floor: "")
        }
        #expect(try f.jpegFiles().isEmpty)
    }

    @Test("Node photo cannot be deleted on its own")
    func prohibitHalfNode() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let tag = try f.save()
            let photo = try NodePhotoAssociation.photo(for: tag)
            #expect(throws: NodeCaptureError.nodePhotoRequiresNodeDeletion) { try f.coordinator.deletePhoto(photo) }
            #expect(throws: NodeCaptureError.invalidAssociation) { try f.store.deleteTag(tag) }
            #expect(try f.files.read(relativePath: photo.filePath) == f.jpeg)
        }
    }

    @Test("Deleting node removes its unique photo, preserving independent historical/scenery data")
    func nodeDeletion() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let legacy = try f.coordinator.addTag(type: .door, note: "old")
            let scenery = try f.coordinator.saveScenery(capture: f.capture(), note: "view")
            let node = try f.save()
            try f.coordinator.deleteTag(node)
            #expect(f.track.tags.map(\.id) == [legacy.id])
            #expect(f.track.photos.map(\.id) == [scenery.id])
            #expect(try f.files.read(relativePath: scenery.filePath) == f.jpeg)
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Node delete DB failure preserves both records and JPEG")
    func deletionFailure() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let node = try f.save()
            let path = try NodePhotoAssociation.photo(for: node).filePath
            f.failure.save = true
            #expect(throws: Stage2Failure.database) { try f.coordinator.deleteTag(node) }
            #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).count == 1)
            #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).count == 1)
            #expect(try f.files.read(relativePath: path) == f.jpeg)
        }
    }

    @Test("Node delete file failure keeps a retryable cleanup warning, no half metadata")
    func deletionCleanupFailure() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let node = try f.save()
            f.files.failDeletes = true
            try f.coordinator.deleteTag(node)
            #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
            #expect(f.coordinator.mediaCleanupMessage != nil)
            f.files.failDeletes = false
            f.coordinator.retryPhotoCleanup(protecting: [])
            #expect(try f.jpegFiles().isEmpty)
            #expect(f.coordinator.mediaCleanupMessage == nil)
        }
    }

    @Test("Duplicate node-photo association is rejected without deleting files")
    func duplicateAssociation() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let node = try f.save()
            let duplicate = TrackPhoto(track: f.track, timeMs: 2000, filePath: "photos/\(f.track.id.uuidString.lowercased())/duplicate.jpg",
                                       createdAt: 2000, kindRawValue: "node", tagID: node.id)
            f.context.insert(duplicate)
            try f.context.save()
            #expect(throws: NodeCaptureError.invalidAssociation) { try f.coordinator.deleteTag(node) }
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Cross-Track duplicate reference is rejected")
    func crossTrackAssociation() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let node = try f.save()
            let other = Track(name: "Other", startedAt: 1)
            f.context.insert(other)
            f.context.insert(TrackPhoto(track: other, timeMs: 2000, filePath: "photos/other/p.jpg",
                                       createdAt: 2000, kindRawValue: "node", tagID: node.id))
            try f.context.save()
            #expect(throws: NodeCaptureError.invalidAssociation) { try f.coordinator.deleteTag(node) }
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Dangling node reference is rejected")
    func danglingAssociation() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let node = try f.save()
            let photo = try NodePhotoAssociation.photo(for: node)
            photo.tagID = UUID()
            try f.context.save()
            #expect(throws: NodeCaptureError.invalidAssociation) { try f.coordinator.deleteTag(node) }
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Area deletion clears node area but preserves binding and bytes")
    func areaDeletion() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let a = Area(name: "A", createdAt: 1)
            f.context.insert(a)
            try f.context.save()
            let tag = try f.coordinator.saveNode(capture: f.capture(), type: .door, note: "", area: a, floor: "2/F")
            let photo = try NodePhotoAssociation.photo(for: tag)
            let photoID = photo.id
            try Phase2DataStore(context: f.context).deleteAreaPreservingContents(a)
            #expect(tag.areaID == nil && tag.areaStateRawValue == "unassigned" && tag.floor == "2/F")
            #expect(try NodePhotoAssociation.photo(for: tag).id == photoID)
            #expect(try f.files.read(relativePath: photo.filePath) == f.jpeg)
        }
    }

    @Test("Legacy tag deletion does not pair or delete matching independent photo")
    func legacyDeletion() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let tag = try f.coordinator.addTag(type: .door, note: "same")
            let photo = try f.coordinator.saveScenery(capture: f.capture(), note: "same")
            photo.kindRawValue = "legacyUnlinked"
            try f.context.save()
            try f.coordinator.deleteTag(tag)
            #expect(f.track.photos.count == 1 && photo.tagID == nil)
            #expect(try f.files.read(relativePath: photo.filePath) == f.jpeg)
            try f.coordinator.deletePhoto(photo)
            #expect(f.track.photos.isEmpty)
        }
    }

    @Test("Deleting completed Track cascades all node/legacy/scenery data and owned directory")
    func trackCascade() async throws {
        let f = try Stage2Fixture()
        defer { f.dispose() }
        _ = try f.save()
        _ = try f.coordinator.addTag(type: .door, note: "old")
        _ = try f.coordinator.saveScenery(capture: f.capture(), note: "")
        try await f.coordinator.stop()
        try f.coordinator.delete(f.track)
        #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("photos/\(f.trackID.uuidString.lowercased())").path))
    }

    @Test("Active Track remains protected from deletion")
    func protectActiveTrack() throws {
        try withFixture { (f: Stage2Fixture) throws in
            _ = try f.save()
            #expect(throws: RecordingError.activeTrackCannotBeDeleted) { try f.coordinator.delete(f.track) }
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("V2 export refuses node relationships even on a legacy Track")
    func exportGate() throws {
        try withFixture { (f: Stage2Fixture) throws in
            _ = try f.save()
            f.track.isGlobalRecording = false
            #expect(throws: ExportValidationError.requiresV3Export) {
                try AreaExportSnapshotBuilder(photoStorage: f.files).buildUnassigned(tracks: [f.track], exportedAt: 3000)
            }
        }
    }

    @Test("Write-before-commit intent survives relaunch and removes an orphan, not referenced JPEG")
    func persistentCleanupJournal() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let orphan = try f.files.local.storeJPEG(f.jpeg, trackID: f.track.id, timeMs: 2000)
            let protected = try f.files.local.storeJPEG(f.jpeg, trackID: f.track.id, timeMs: 2000)
            let reopened = try LocalPhotoFileStore(rootURL: f.root)
            try reopened.retryPendingCleanup(protecting: [protected])
            #expect(throws: (any Error).self) { try reopened.read(relativePath: orphan) }
            #expect(try reopened.read(relativePath: protected) == f.jpeg)
            #expect(try f.jpegFiles().count == 1)
        }
    }

    @Test("Cleanup journal traversal is rejected, external file remains intact")
    func poisonedJournal() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let marker = f.root.appendingPathComponent("outside.txt")
            let bytes = Data("keep".utf8)
            try bytes.write(to: marker)
            try JSONEncoder().encode(["photos/../outside.txt"]).write(to: f.root.appendingPathComponent("photo-cleanup.json"))
            #expect(throws: PhotoStorageError.unsafeRelativePath) {
                try f.files.local.retryPendingCleanup(protecting: [])
            }
            #expect(try Data(contentsOf: marker) == bytes)
        }
    }

    @Test("Cleanup journal symlink escape is rejected")
    func journalSymlink() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let external = f.root.deletingLastPathComponent().appendingPathComponent("Stage2-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: external) }
            let bytes = Data("[]".utf8)
            try bytes.write(to: external)
            try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("photo-cleanup.json"),
                                                       withDestinationURL: external)
            #expect(throws: PhotoStorageError.unsafeRelativePath) {
                try f.files.local.retryPendingCleanup(protecting: [])
            }
            #expect(try Data(contentsOf: external) == bytes)
        }
    }

    @Test("Cleanup never removes a directory with a referenced descendant")
    func protectedDirectory() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let path = try f.files.local.storeJPEG(f.jpeg, trackID: f.track.id, timeMs: 2000)
            let directory = "photos/\(f.trackID.uuidString.lowercased())"
            try JSONEncoder().encode([directory]).write(to: f.root.appendingPathComponent("photo-cleanup.json"))
            try f.files.local.retryPendingCleanup(protecting: [path])
            #expect(try f.files.read(relativePath: path) == f.jpeg)
        }
    }

    @Test("Cleanup protection canonicalizes an internal symlink alias before comparing references")
    func protectedAlias() throws {
        try withFixture { (f: Stage2Fixture) throws in
            let path = try f.files.local.storeJPEG(f.jpeg, trackID: f.trackID, timeMs: 2000)
            let alias = f.root.appendingPathComponent("photos/alias")
            try FileManager.default.createSymbolicLink(at: alias,
                withDestinationURL: f.root.appendingPathComponent("photos/\(f.trackID.uuidString.lowercased())"))
            let reference = "photos/alias/" + URL(fileURLWithPath: path).lastPathComponent
            try f.files.local.retryPendingCleanup(protecting: [reference])
            #expect(try f.files.read(relativePath: path) == f.jpeg)
        }
    }

    private func state(heading: Double) -> LiveSensorState {
        LiveSensorState(permission: .denied, location: .unavailable, pressureHpa: .unavailable,
                        magneticField: .unavailable,
                        headingDeg: .available(TimestampedSensorValue(value: heading, capturedAt: Date())))
    }

    private func withFixture(_ body: (Stage2Fixture) throws -> Void) throws {
        let f = try Stage2Fixture()
        defer { f.dispose() }
        try body(f)
    }
}

private enum Stage2Failure: Error { case database, file, deletion }

@MainActor
private final class Stage2SaveFailure { var save = false }

@MainActor
private final class Stage2Fixture {
    let root: URL
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let failure = Stage2SaveFailure()
    let files: Stage2PhotoStore
    let hub = Stage2Hub()
    let ticker = Stage2Ticker()
    let store: SwiftDataRecordingStore
    let coordinator: RecordingCoordinator
    let track: Track
    let trackID: UUID
    let jpeg: Data

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RoomMarkerStage2-\(UUID())")
        container = try RoomMarkerModelContainer.make(inMemory: true)
        files = Stage2PhotoStore(local: try LocalPhotoFileStore(rootURL: root))
        let failure = failure
        store = SwiftDataRecordingStore(context: container.mainContext) {
            if failure.save { throw Stage2Failure.database }
            try $0.save()
        }
        coordinator = RecordingCoordinator(hub: hub, ticker: ticker, persistence: store,
                                           mediaPersistence: store, photoStorage: files, nowMilliseconds: { 1000 })
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        try coordinator.start(name: "Synthetic Stage 2")
        track = try #require(coordinator.activeTrack)
        trackID = track.id
    }

    func capture() throws -> CapturedTrackPhoto {
        try #require(try coordinator.freezePhotoCapture(.success(jpegData: jpeg, capturedAt: 2000)))
    }

    func save(type: TrackTagType = .door) throws -> TrackTag {
        try coordinator.saveNode(capture: capture(), type: type, note: "", area: nil, floor: "")
    }

    func jpegFiles() throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jpg" }
    }

    func dispose() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class Stage2Hub: SensorHubProtocol {
    var state = LiveSensorState.waiting
    var consumers: Set<SensorConsumer> = []
    var activeConsumerCount: Int { consumers.count }
    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) { consumers.insert(consumer) }
    func stop(consumer: SensorConsumer) { consumers.remove(consumer) }
    func requestLocationAuthorization() {}
}

@MainActor
private final class Stage2Ticker: RecordingTicking {
    var starts = 0
    func start(handler: @escaping Handler) { starts += 1 }
    func stop() async {}
}

@MainActor
private final class Stage2Camera: CameraServicing {
    var authorizationState: CameraAuthorizationState
    var isCameraAvailable = true
    var requests = 0
    init(state: CameraAuthorizationState) { authorizationState = state }
    func requestAuthorization() async -> CameraAuthorizationState {
        requests += 1
        authorizationState = .authorized
        return authorizationState
    }
}

@MainActor
private final class Stage2PhotoStore: PhotoFileStoring {
    let local: LocalPhotoFileStore
    var failWrites = false
    var failDeletes = false
    init(local: LocalPhotoFileStore) { self.local = local }
    func storeJPEG(_ data: Data, trackID: UUID, timeMs: Int64) throws -> String {
        if failWrites { throw Stage2Failure.file }
        return try local.storeJPEG(data, trackID: trackID, timeMs: timeMs)
    }
    func read(relativePath: String) throws -> Data { try local.read(relativePath: relativePath) }
    func validate(relativePath: String) throws { try local.validate(relativePath: relativePath) }
    func confirmReferenced(relativePath: String) throws { try local.confirmReferenced(relativePath: relativePath) }
    func prepareDeletion(relativePath: String) throws { try local.prepareDeletion(relativePath: relativePath) }
    func delete(relativePath: String) throws {
        if failDeletes { throw Stage2Failure.deletion }
        try local.delete(relativePath: relativePath)
    }
    func deleteTrackDirectory(trackID: UUID) throws { try local.deleteTrackDirectory(trackID: trackID) }
    func retryPendingCleanup(protecting referencedPaths: Set<String>) throws {
        if failDeletes { throw Stage2Failure.deletion }
        try local.retryPendingCleanup(protecting: referencedPaths)
    }
}
