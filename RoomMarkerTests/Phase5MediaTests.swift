import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Phase 5 tags and photos")
@MainActor
struct Phase5MediaTests {
    @Test("1. An active Track accepts a TrackTag")
    func activeTrackCreatesTag() throws {
        let fixture = makeFixture()
        try fixture.start()

        let tag = try fixture.coordinator.addTag(type: .door, note: "测试门")

        #expect(fixture.media.tags.count == 1)
        #expect(tag.track?.id == fixture.coordinator.activeTrackID)
        #expect(tag.tagTypeRawValue == "门")
    }

    @Test("2. All six tag raw values remain HarmonyOS-compatible")
    func exactTagRawValues() {
        #expect(TrackTagType.allCases.map(\.rawValue) == [
            "厕所", "楼梯", "门", "门禁", "电梯", "教室",
        ])
    }

    @Test("3. Optional tag notes are trimmed and persisted")
    func tagNotePersists() throws {
        let fixture = makeFixture()
        try fixture.start()

        let tag = try fixture.coordinator.addTag(type: .stairs, note: "  三楼  ")

        #expect(tag.note == "三楼")
    }

    @Test("4. A tag receives complete fresh synthetic metadata")
    func tagCompleteMetadata() throws {
        let fixture = makeFixture(state: completeState())
        try fixture.start()

        let tag = try fixture.coordinator.addTag(type: .elevator, note: "")

        #expect(tag.latitude == 22.3)
        #expect(tag.longitude == 114.2)
        #expect(tag.altitude == 18)
        #expect(tag.headingDeg == 90)
    }

    @Test("5. A tag accepts partial metadata")
    func tagPartialMetadata() throws {
        let fixture = makeFixture(state: LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: 22.31,
                longitude: 114.21,
                altitude: nil,
                horizontalAccuracy: nil
            )),
            pressureHpa: .unavailable,
            magneticField: .unsupported,
            headingDeg: .stale(TimestampedSensorValue(value: 12, capturedAt: Date()))
        ))
        try fixture.start()

        let tag = try fixture.coordinator.addTag(type: .classroom, note: "")

        #expect(tag.latitude == 22.31)
        #expect(tag.longitude == 114.21)
        #expect(tag.altitude == nil)
        #expect(tag.headingDeg == nil)
    }

    @Test("6. A tag with no sensor metadata remains valid")
    func tagWithoutMetadata() throws {
        let fixture = makeFixture(state: .waiting)
        try fixture.start()

        let tag = try fixture.coordinator.addTag(type: .toilet, note: "")

        #expect(tag.latitude == nil)
        #expect(tag.longitude == nil)
        #expect(tag.altitude == nil)
        #expect(tag.headingDeg == nil)
    }

    @Test("7. Missing and non-finite tag values never become zero")
    func tagNeverFabricatesZero() throws {
        let fixture = makeFixture(state: LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: .nan,
                longitude: .infinity,
                altitude: -.infinity,
                horizontalAccuracy: nil
            )),
            pressureHpa: .unavailable,
            magneticField: .unavailable,
            headingDeg: .unavailable
        ))
        try fixture.start()

        let tag = try fixture.coordinator.addTag(type: .gate, note: "")

        #expect(tag.latitude == nil)
        #expect(tag.longitude == nil)
        #expect(tag.altitude == nil)
        #expect(tag.headingDeg == nil)
    }

    @Test("8. Tag creation without an active Track is rejected")
    func tagWithoutActiveTrackRejected() {
        let fixture = makeFixture()

        #expect(throws: TrackMediaError.noActiveTrack) {
            try fixture.coordinator.addTag(type: .door, note: "")
        }
        #expect(fixture.media.tags.isEmpty)
    }

    @Test("9. Photo storage returns a relative owned path")
    func storageReturnsRelativePath() throws {
        try withPhotoStore { store, _ in
            let path = try store.storeJPEG(jpegData(), trackID: UUID(), timeMs: 123)

            #expect(path.hasPrefix("photos/"))
            #expect(!path.hasPrefix("/"))
            #expect(path.hasSuffix(".jpg"))
        }
    }

    @Test("10. Stored JPEG data is readable through the abstraction")
    func storedDataReadable() throws {
        try withPhotoStore { store, _ in
            let data = jpegData()
            let path = try store.storeJPEG(data, trackID: UUID(), timeMs: 123)

            #expect(try store.read(relativePath: path) == data)
        }
    }

    @Test("11. Generated paths remain unique at the same timestamp")
    func generatedPathsUnique() throws {
        try withPhotoStore { store, _ in
            let trackID = UUID()
            let first = try store.storeJPEG(jpegData(), trackID: trackID, timeMs: 123)
            let second = try store.storeJPEG(jpegData(), trackID: trackID, timeMs: 123)

            #expect(first != second)
        }
    }

    @Test("12. Storage rejects paths that escape the owned photo root")
    func pathEscapeRejected() throws {
        try withPhotoStore { store, _ in
            #expect(throws: PhotoStorageError.unsafeRelativePath) {
                try store.read(relativePath: "photos/../../outside.jpg")
            }
            #expect(throws: PhotoStorageError.unsafeRelativePath) {
                try store.delete(relativePath: "/tmp/outside.jpg")
            }
        }
    }

    @Test("13. An unavailable fake camera creates no TrackPhoto")
    func unavailableCameraCreatesNothing() throws {
        let camera = FakeCameraService(
            authorizationState: .authorized,
            isCameraAvailable: false
        )
        let fixture = makeFixture()
        try fixture.start()

        #expect(camera.authorizationState == .authorized)
        #expect(!camera.isCameraAvailable)
        #expect(try fixture.coordinator.handlePhotoCapture(.unavailable) == nil)
        #expect(fixture.media.photos.isEmpty)
        #expect(fixture.files.stored.isEmpty)
    }

    @Test("14. Camera cancellation creates no TrackPhoto")
    func cameraCancellationCreatesNothing() throws {
        let fixture = makeFixture()
        try fixture.start()

        #expect(try fixture.coordinator.handlePhotoCapture(.cancelled) == nil)
        #expect(fixture.media.photos.isEmpty)
        #expect(fixture.files.stored.isEmpty)
    }

    @Test("15. Capture failure creates no TrackPhoto")
    func captureFailureCreatesNothing() throws {
        let fixture = makeFixture()
        try fixture.start()

        #expect(throws: TrackMediaError.captureFailed("synthetic")) {
            try fixture.coordinator.handlePhotoCapture(.failed("synthetic"))
        }
        #expect(fixture.media.photos.isEmpty)
        #expect(fixture.files.stored.isEmpty)
    }

    @Test("16. File-write failure creates no metadata")
    func fileWriteFailureCreatesNoMetadata() throws {
        let fixture = makeFixture()
        fixture.files.failWrites = true
        try fixture.start()

        #expect(throws: FakeMediaFailure.fileWrite) {
            try fixture.coordinator.handlePhotoCapture(
                .success(jpegData: jpegData(), capturedAt: 2_000)
            )
        }
        #expect(fixture.media.photos.isEmpty)
    }

    @Test("17. Successful write and metadata save create one TrackPhoto")
    func photoWriteThenMetadata() throws {
        let fixture = makeFixture(state: completeState())
        try fixture.start()

        let photo = try #require(try fixture.coordinator.handlePhotoCapture(
            .success(jpegData: jpegData(), capturedAt: 2_000),
            note: "  门口  "
        ))

        #expect(fixture.files.stored.count == 1)
        #expect(fixture.media.photos.count == 1)
        #expect(photo.filePath.hasPrefix("photos/"))
        #expect(photo.note == "门口")
        #expect(photo.latitude == 22.3)
        #expect(photo.headingDeg == 90)
    }

    @Test("18. Metadata failure attempts orphan-file cleanup")
    func metadataFailureCleansOrphan() throws {
        let fixture = makeFixture()
        fixture.media.failPhotoCreate = true
        try fixture.start()

        #expect(throws: FakeMediaFailure.metadataWrite) {
            try fixture.coordinator.handlePhotoCapture(
                .success(jpegData: jpegData(), capturedAt: 2_000)
            )
        }
        #expect(fixture.files.deleteAttempts == 1)
        #expect(fixture.files.stored.isEmpty)
        #expect(fixture.media.photos.isEmpty)
    }

    @Test("19. Individual TrackPhoto deletion removes metadata and file")
    func individualPhotoDeletion() throws {
        let fixture = makeFixture()
        try fixture.start()
        let photo = try #require(try fixture.coordinator.handlePhotoCapture(
            .success(jpegData: jpegData(), capturedAt: 2_000)
        ))

        try fixture.coordinator.deletePhoto(photo)

        #expect(fixture.media.photos.isEmpty)
        #expect(fixture.files.stored.isEmpty)
    }

    @Test("20. Track deletion removes its owned photo directory")
    func trackDeletionCleansPhotoDirectory() throws {
        let fixture = makeFixture()
        let track = Track(name: "Ended", area: fixture.area, startedAt: 1, endedAt: 2)
        fixture.recording.tracks.append(track)

        try fixture.coordinator.delete(track)

        #expect(fixture.recording.tracks.isEmpty)
        #expect(fixture.files.deletedTrackDirectories == [track.id])
    }

    @Test("21. SwiftData Track deletion cascades TrackTag metadata")
    func trackDeletionCascadesTags() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Area", createdAt: 1)
        let track = Track(name: "Track", area: area, startedAt: 2)
        context.insert(area)
        context.insert(track)
        context.insert(TrackTag(
            track: track,
            timeMs: 3,
            tagType: .door,
            createdAt: 3
        ))
        try context.save()

        try SwiftDataRecordingStore(context: context).delete(track)

        #expect(try context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
    }

    @Test("22. SwiftData Track deletion cascades TrackPhoto metadata")
    func trackDeletionCascadesPhotos() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Area", createdAt: 1)
        let track = Track(name: "Track", area: area, startedAt: 2)
        context.insert(area)
        context.insert(track)
        context.insert(TrackPhoto(
            track: track,
            timeMs: 3,
            filePath: "photos/test/photo.jpg",
            createdAt: 3
        ))
        try context.save()

        try SwiftDataRecordingStore(context: context).delete(track)

        #expect(try context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
    }

    @Test("23. Missing photo files return a safe missing state")
    func missingPhotoSafe() throws {
        try withPhotoStore { store, _ in
            let content = PhotoContentLoader(storage: store).load(
                relativePath: "photos/00000000-0000-0000-0000-000000000000/missing.jpg"
            )

            #expect(content.status == .missing)
            #expect(content.image == nil)
        }
    }

    @Test("24. Corrupt photo data returns a safe corrupt state")
    func corruptPhotoSafe() throws {
        try withPhotoStore { store, _ in
            let path = try store.storeJPEG(Data("not a jpeg".utf8), trackID: UUID(), timeMs: 1)
            let content = PhotoContentLoader(storage: store).load(relativePath: path)

            #expect(content.status == .corrupt)
            #expect(content.image == nil)
        }
    }

    @Test("25. Adding a tag does not disrupt active recording")
    func tagKeepsRecordingActive() throws {
        let fixture = makeFixture()
        try fixture.start()
        let trackID = fixture.coordinator.activeTrackID

        try fixture.coordinator.addTag(type: .door, note: "")

        #expect(fixture.coordinator.state == .recording(trackID: try #require(trackID)))
        #expect(fixture.ticker.startCalls == 1)
        #expect(fixture.hub.consumers == [.recording])
    }

    @Test("26. A photo action creates no second recording session")
    func photoCreatesNoSecondSession() throws {
        let fixture = makeFixture()
        try fixture.start()
        let trackID = fixture.coordinator.activeTrackID

        _ = try fixture.coordinator.handlePhotoCapture(
            .success(jpegData: jpegData(), capturedAt: 2_000)
        )

        #expect(fixture.recording.tracks.count == 1)
        #expect(fixture.ticker.startCalls == 1)
        #expect(fixture.coordinator.activeTrackID == trackID)
    }

    @Test("27. Tag and photo actions preserve five-point batch semantics")
    func mediaPreservesPointBatching() async throws {
        let fixture = makeFixture()
        try fixture.start()
        for time in 1...3 { await fixture.ticker.fire(at: Int64(time * 1_000)) }
        try fixture.coordinator.addTag(type: .door, note: "")
        _ = try fixture.coordinator.handlePhotoCapture(
            .success(jpegData: jpegData(), capturedAt: 3_500)
        )
        for time in 4...7 { await fixture.ticker.fire(at: Int64(time * 1_000)) }

        try await fixture.coordinator.stop()

        #expect(fixture.recording.batches.map(\.count) == [5, 2])
        #expect(fixture.recording.persistedDrafts.map(\.timeMs) == [
            1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000,
        ])
    }

    private func makeFixture(state: LiveSensorState = .waiting) -> Phase5Fixture {
        let hub = Phase5SensorHub(state: state)
        let ticker = Phase5Ticker()
        let recording = Phase5RecordingStore()
        let media = Phase5MediaStore()
        let files = Phase5PhotoStore()
        let clock = Phase5Clock(value: 1_000)
        let coordinator = RecordingCoordinator(
            hub: hub,
            ticker: ticker,
            persistence: recording,
            mediaPersistence: media,
            photoStorage: files,
            nowMilliseconds: { clock.value }
        )
        return Phase5Fixture(
            coordinator: coordinator,
            hub: hub,
            ticker: ticker,
            recording: recording,
            media: media,
            files: files,
            clock: clock,
            area: Area(name: "Media Area", createdAt: 1)
        )
    }

    private func completeState() -> LiveSensorState {
        LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: 22.3,
                longitude: 114.2,
                altitude: 18,
                horizontalAccuracy: 3
            )),
            pressureHpa: available(1008),
            magneticField: available(MagneticFieldReading(x: 1, y: 2, z: 3)),
            headingDeg: available(90)
        )
    }

    private func available<Value: Sendable>(_ value: Value) -> SensorValueState<Value> {
        .available(TimestampedSensorValue(value: value, capturedAt: Date()))
    }

    private func jpegData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data([0xFF, 0xD8, 0xFF, 0xD9])
    }

    private func withPhotoStore(
        _ body: (LocalPhotoFileStore, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomMarkerPhase5-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalPhotoFileStore(rootURL: root)
        try body(store, root)
    }
}

@MainActor
private struct Phase5Fixture {
    let coordinator: RecordingCoordinator
    let hub: Phase5SensorHub
    let ticker: Phase5Ticker
    let recording: Phase5RecordingStore
    let media: Phase5MediaStore
    let files: Phase5PhotoStore
    let clock: Phase5Clock
    let area: Area

    func start() throws {
        try coordinator.start(name: "Media Track", area: area)
    }
}

@MainActor
private final class Phase5Clock {
    var value: Int64
    init(value: Int64) { self.value = value }
}

@MainActor
private final class Phase5SensorHub: SensorHubProtocol {
    var state: LiveSensorState
    var consumers: Set<SensorConsumer> = []
    var activeConsumerCount: Int { consumers.count }

    init(state: LiveSensorState) { self.state = state }

    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) {
        consumers.insert(consumer)
    }

    func requestLocationAuthorization() {}

    func stop(consumer: SensorConsumer) {
        consumers.remove(consumer)
    }
}

@MainActor
private final class Phase5Ticker: RecordingTicking {
    private var handler: Handler?
    private(set) var startCalls = 0

    func start(handler: @escaping Handler) {
        startCalls += 1
        self.handler = handler
    }

    func stop() async {
        handler = nil
    }

    func fire(at timeMs: Int64) async {
        guard let handler else { return }
        if !(await handler(timeMs)) { self.handler = nil }
    }
}

@MainActor
private final class Phase5RecordingStore: RecordingPersisting {
    var tracks: [Track] = []
    var batches: [[TrackPointDraft]] = []
    var persistedDrafts: [TrackPointDraft] = []

    func createTrack(name: String, area: Area, startedAt: Int64) throws -> Track {
        let track = Track(name: name, area: area, startedAt: startedAt)
        tracks.append(track)
        return track
    }

    func append(_ drafts: [TrackPointDraft], to track: Track) throws {
        batches.append(drafts)
        persistedDrafts.append(contentsOf: drafts)
    }

    func finalize(_ track: Track, endedAt: Int64) throws {
        track.endedAt = endedAt
    }

    func delete(_ track: Track) throws {
        tracks.removeAll { $0.id == track.id }
    }
}

private enum FakeMediaFailure: Error, Equatable {
    case fileWrite
    case metadataWrite
}

@MainActor
private final class Phase5MediaStore: TrackMediaPersisting {
    var tags: [TrackTag] = []
    var photos: [TrackPhoto] = []
    var failPhotoCreate = false

    func createTag(_ draft: TrackTagDraft, for track: Track) throws -> TrackTag {
        let tag = TrackTag(
            track: track,
            timeMs: draft.timeMs,
            tagType: draft.tagType,
            note: draft.note,
            latitude: draft.metadata.latitude,
            longitude: draft.metadata.longitude,
            altitude: draft.metadata.altitude,
            headingDeg: draft.metadata.headingDeg,
            createdAt: draft.createdAt
        )
        tags.append(tag)
        return tag
    }

    func createPhoto(_ draft: TrackPhotoDraft, for track: Track) throws -> TrackPhoto {
        if failPhotoCreate { throw FakeMediaFailure.metadataWrite }
        let photo = TrackPhoto(
            track: track,
            timeMs: draft.timeMs,
            filePath: draft.filePath,
            note: draft.note,
            latitude: draft.metadata.latitude,
            longitude: draft.metadata.longitude,
            altitude: draft.metadata.altitude,
            headingDeg: draft.metadata.headingDeg,
            createdAt: draft.createdAt
        )
        photos.append(photo)
        return photo
    }

    func deleteTag(_ tag: TrackTag) throws {
        tags.removeAll { $0.id == tag.id }
    }

    func deletePhoto(_ photo: TrackPhoto) throws {
        photos.removeAll { $0.id == photo.id }
    }
}

@MainActor
private final class Phase5PhotoStore: PhotoFileStoring {
    var stored: [String: Data] = [:]
    var failWrites = false
    var deleteAttempts = 0
    var deletedTrackDirectories: [UUID] = []

    func storeJPEG(_ data: Data, trackID: UUID, timeMs: Int64) throws -> String {
        if failWrites { throw FakeMediaFailure.fileWrite }
        let path = "photos/\(trackID.uuidString.lowercased())/\(timeMs)-test.jpg"
        stored[path] = data
        return path
    }

    func read(relativePath: String) throws -> Data {
        guard let data = stored[relativePath] else { throw PhotoStorageError.missingFile }
        return data
    }

    func validate(relativePath: String) throws {
        guard relativePath.hasPrefix("photos/"), !relativePath.contains("..") else {
            throw PhotoStorageError.unsafeRelativePath
        }
    }

    func delete(relativePath: String) throws {
        deleteAttempts += 1
        stored.removeValue(forKey: relativePath)
    }

    func deleteTrackDirectory(trackID: UUID) throws {
        deletedTrackDirectories.append(trackID)
        let prefix = "photos/\(trackID.uuidString.lowercased())/"
        stored = stored.filter { !$0.key.hasPrefix(prefix) }
    }
}

@MainActor
private final class FakeCameraService: CameraServicing {
    var authorizationState: CameraAuthorizationState
    var isCameraAvailable: Bool

    init(authorizationState: CameraAuthorizationState, isCameraAvailable: Bool) {
        self.authorizationState = authorizationState
        self.isCameraAvailable = isCameraAvailable
    }

    func requestAuthorization() async -> CameraAuthorizationState {
        authorizationState
    }
}
