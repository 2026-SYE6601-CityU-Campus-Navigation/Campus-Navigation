import CoreMotion
import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 4 raw IMU", .serialized)
@MainActor
struct Stage4IMUTests {
    @Test("Motion privacy text describes raw IMU while existing launch, location and camera declarations remain")
    func privacyConfiguration() throws {
        let text = try #require(Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") as? String)
        #expect(["加速度", "角速度", "磁场", "气压", "室内导航"].allSatisfy { text.contains($0) })
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String != nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String != nil)
        #expect((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any] != nil)
    }

    @Test("Raw IMU is opt-in and never starts for a default recording")
    func optIn() async throws {
        let f = try Stage4Fixture(enabled: false)
        defer { f.dispose() }
        #expect(!f.track.rawIMURequested && f.track.rawIMUInterval == nil)
        #expect(f.service.starts == 0 && f.track.imuBatches.isEmpty)
        try await f.coordinator.stop()
        #expect(f.track.rawAccelState == "notRequested" && f.track.rawGyroState == "notRequested")
    }

    @Test("Requested streams use 50 Hz independently, never turn into TrackPoints")
    func independentStreams() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        #expect(f.track.rawIMURequested && f.track.rawIMUInterval == 0.02)
        #expect(f.service.intervals == [0.02])
        f.emit(.accelerometer, at: 101, x: 0, y: 0, z: -1)
        f.emit(.gyroscope, at: 101, x: 0.1, y: -0.2, z: 0.3)
        f.clock.wall = 3000
        try await f.coordinator.stop()
        let samples = try f.samples()
        #expect(samples.count == 2 && f.track.points.isEmpty)
        #expect(samples[0].x == 0 && samples[0].z == -1 && samples[1].y == -0.2)
        #expect(RawIMUKind.accelerometer.unit == "g" && RawIMUKind.gyroscope.unit == "rad/s")
        #expect(f.track.rawAccelState == "stopped" && f.track.rawGyroState == "stopped")
    }

    @Test("Fixed uptime anchor retains measurement time despite delayed callbacks and UTC clock jumps")
    func anchoredTime() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.clock.uptime = 110
        f.clock.wall = 90000
        f.service.emit(.reading(.init(kind: .accelerometer, sensorTimeSeconds: 101, x: 1, y: 2, z: 3)))
        f.clock.wall = 80000
        f.service.emit(.reading(.init(kind: .accelerometer, sensorTimeSeconds: 102, x: 4, y: 5, z: 6)))
        try await f.coordinator.stop()
        let samples = try f.samples()
        #expect(samples.map(\.timeMs) == [2000, 3000])
        #expect(samples.map(\.sensorTimeSeconds) == [101, 102])
        #expect(samples.map(\.receivedAtMs) == [90000, 80000])
    }

    @Test("Duplicate, backward, pre-start, future and nonfinite input is rejected without replacement")
    func invalidEvents() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 101)
        for time in [101.0, 100.5, 99.0, Double.nan, Double.infinity, 500] {
            f.service.emit(.reading(.init(kind: .accelerometer, sensorTimeSeconds: time, x: 1, y: 2, z: 3)))
        }
        f.service.emit(.reading(.init(kind: .gyroscope, sensorTimeSeconds: 101, x: .nan, y: 0, z: 0)))
        #expect(f.imu.acceptedCount == 1 && f.imu.status.rejectedCount == 7)
        f.clock.wall = 3000
        try await f.coordinator.stop()
        #expect(try f.samples().count == 1 && f.track.rawIMURejectedCount == 7)
    }

    @Test("Unsupported or denied channels do not fabricate data or trigger a prompt loop", arguments: [RawIMUChannelState.unsupported, .denied, .unavailable])
    func unavailable(_ state: RawIMUChannelState) async throws {
        let f = try Stage4Fixture(channelState: state)
        defer { f.dispose() }
        #expect(f.imu.status.accelerometer == state && f.imu.status.gyroscope == state)
        f.emit(.accelerometer, at: 101)
        f.emit(.gyroscope, at: 101)
        #expect(f.imu.acceptedCount == 0 && f.service.starts == 1)
        try await f.coordinator.stop()
        #expect(f.track.imuBatches.isEmpty && f.track.rawAccelState == state.rawValue)
    }

    @Test("One unavailable channel does not block the other")
    func partialHardware() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.service.emit(.state(.gyroscope, .unsupported))
        f.emit(.gyroscope, at: 101)
        f.emit(.accelerometer, at: 101)
        f.clock.wall = 3000
        try await f.coordinator.stop()
        #expect(try f.samples().map(\.kind) == [.accelerometer])
        #expect(f.track.rawGyroState == "unsupported")
    }

    @Test("Native Core Motion errors distinguish denied from unavailable")
    func errorClassification() {
        #expect(CoreMotionRawIMUService.failureState(nil) == nil)
        for code in [CMErrorNotAuthorized, CMErrorMotionActivityNotAuthorized] {
            #expect(CoreMotionRawIMUService.failureState(NSError(domain: CMErrorDomain, code: Int(code.rawValue))) == .denied)
        }
        #expect(CoreMotionRawIMUService.failureState(NSError(domain: CMErrorDomain, code: Int(CMErrorNotAvailable.rawValue))) == .unavailable)
        #expect(CoreMotionRawIMUService.failureState(NSError(domain: "Other", code: Int(CMErrorNotAuthorized.rawValue))) == .unavailable)
    }

    @Test("100-event batches and a final tail persist each callback exactly once")
    func batchAndTail() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        for index in 1...205 {
            f.emit(index.isMultiple(of: 2) ? .gyroscope : .accelerometer, at: 100 + Double(index) * 0.02)
        }
        #expect(f.track.imuBatches.count == 2 && f.imu.pendingCount == 5)
        #expect(f.track.imuBatches.allSatisfy { $0.sampleCount == 100 })
        f.clock.wall = 6000
        try await f.coordinator.stop()
        #expect(f.track.imuBatches.map(\.sampleCount).sorted() == [5, 100, 100])
        #expect(try f.samples().count == 205 && f.imu.pendingCount == 0)
        #expect(f.track.imuBatches.reduce(0) { $0 + $1.accelerationCount } == 103)
        #expect(f.track.imuBatches.reduce(0) { $0 + $1.gyroscopeCount } == 102)
    }

    @Test("Batch save failure stops only raw IMU, bounds pending memory and permits exact retry")
    func failureRetry() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.failure.enabled = true
        for index in 1...110 { f.emit(.accelerometer, at: 100 + Double(index) * 0.02) }
        #expect(f.imu.acceptedCount == 100 && f.imu.pendingCount == 100)
        #expect(f.imu.errorMessage != nil && f.coordinator.isRecording)
        #expect(f.track.imuBatches.isEmpty && f.hub.activeConsumerCount == 1)
        #expect(!f.context.hasChanges)
        f.failure.enabled = false
        f.clock.wall = 4000
        await f.ticker.fire(4000)
        try f.imu.retry()
        #expect(f.imu.pendingCount == 0 && f.service.starts == 2 && f.imu.errorMessage == nil)
        f.emit(.accelerometer, at: 104)
        f.clock.wall = 6000
        try await f.coordinator.stop()
        #expect(try f.samples().count == 101 && f.track.points.map(\.timeMs) == [4000])
    }

    @Test("A save committed before reporting failure is retried with the same batch ID")
    func committedThenFailed() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.failure.afterCommit = true
        for index in 1...100 { f.emit(.gyroscope, at: 100 + Double(index) * 0.02) }
        #expect(f.track.imuBatches.count == 1 && f.imu.pendingCount == 100)
        let id = try #require(f.track.imuBatches.first?.id)
        f.failure.afterCommit = false
        try f.imu.retry()
        #expect(f.track.imuBatches.map(\.id) == [id] && f.imu.pendingCount == 0)
        #expect(try f.samples().count == 100)
    }

    @Test("Stop failure cannot discard the pending tail or start another Track")
    func stopFailure() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 101)
        f.clock.wall = 2500
        await f.ticker.fire(2500)
        f.failure.enabled = true
        await #expect(throws: Stage4Failure.save) { try await f.coordinator.stop() }
        await f.coordinator.resetFailure()
        #expect(f.coordinator.state.phase == .failed && f.imu.pendingCount == 1 && !f.imu.canStart)
        #expect(throws: RecordingError.alreadyActive) { try f.coordinator.start(name: "Blocked", collectRawIMU: true) }
        f.failure.enabled = false
        await f.coordinator.resetFailure()
        #expect(f.coordinator.state == .idle && f.imu.canStart && f.imu.pendingCount == 0)
        #expect(try f.samples().count == 1 && f.track.endedAt == nil)
        #expect(f.track.points.map(\.timeMs) == [2500])
        f.clock.wall = 3000
        try f.coordinator.finalizeInterrupted(f.track)
        #expect(f.track.endedAt == 3000)
    }

    @Test("Background flushes and pauses raw IMU; foreground resumes with a real gap and same session")
    func backgroundGap() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 101)
        let trackID = f.track.id
        f.coordinator.handleLifecycleTransition(.background)
        #expect(f.imu.pendingCount == 0 && f.track.rawAccelState == "paused")
        f.clock.wall = 62000
        f.clock.uptime = 161
        f.service.emitOld(.reading(.init(kind: .accelerometer, sensorTimeSeconds: 140, x: 0, y: 0, z: -1)), index: 0)
        #expect(f.imu.acceptedCount == 1)
        f.coordinator.handleLifecycleTransition(.active)
        f.coordinator.handleLifecycleTransition(.active)
        f.emit(.accelerometer, at: 162)
        f.clock.wall = 64000
        try await f.coordinator.stop()
        #expect(try f.samples().map(\.timeMs) == [2000, 63000])
        #expect(f.track.id == trackID && f.service.starts == 2 && f.ticker.starts == 1 && f.hub.starts == 1)
        #expect(try f.context.fetch(FetchDescriptor<Track>()).count == 1)
    }

    @Test("Late callbacks from an old generation cannot contaminate a new session")
    func staleSession() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 101)
        f.clock.wall = 3000
        try await f.coordinator.stop()
        try f.coordinator.start(name: "Next", collectRawIMU: true)
        let next = try #require(f.coordinator.activeTrack)
        f.service.emitOld(.reading(.init(kind: .gyroscope, sensorTimeSeconds: 101, x: 1, y: 2, z: 3)), index: 0)
        #expect(f.imu.acceptedCount == 0 && next.imuBatches.isEmpty)
        try await f.coordinator.stop()
        #expect(try f.samples().count == 1)
    }

    @Test("Measurement time assigns delayed callbacks to old or new segments, including exact boundary")
    func segmentMembership() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let first = try #require(f.coordinator.activeSegment?.id)
        f.emit(.accelerometer, at: 101)
        f.clock.wall = 3000
        f.clock.uptime = 102
        try f.coordinator.changeEnvironment(to: .outdoor)
        let second = try #require(f.coordinator.activeSegment?.id)
        f.service.emit(.reading(.init(kind: .accelerometer, sensorTimeSeconds: 101.5, x: 0, y: 0, z: -1)))
        f.emit(.gyroscope, at: 102)
        f.emit(.accelerometer, at: 103)
        f.clock.wall = 5000
        try await f.coordinator.stop()
        let samples = try f.samples()
        #expect(samples.map(\.segmentID) == [first, first, second, second])
        #expect(samples.map(\.timeMs) == [2000, 2500, 3000, 4000])
        #expect(f.track.segments.count == 2)
    }

    @Test("A boundary cannot be backdated across a not-yet-flushed raw sample")
    func pendingBoundaryGuard() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 102)
        f.clock.wall = 2500
        #expect(throws: TrackStructureError.invalidTimestamp) { try f.coordinator.changeEnvironment(to: .outdoor) }
        #expect(f.track.segments.count == 1 && f.imu.pendingCount == 1)
    }

    @Test("Nodes, legacy media, corners, points and source JPEG bytes survive repeated raw batch rollback")
    func graphPreservation() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let ids = try f.addEvidence()
        f.failure.enabled = true
        f.emit(.accelerometer, at: 102)
        #expect(throws: Stage4Failure.save) { try f.imu.stopAndFlush() }
        #expect(throws: Stage4Failure.save) { try f.imu.stopAndFlush() }
        #expect(!f.context.hasChanges && f.track.imuBatches.isEmpty)
        #expect(f.track.tags.map(\.id).sorted(by: uuidOrder) == ids.tags.sorted(by: uuidOrder))
        #expect(f.track.photos.map(\.id).sorted(by: uuidOrder) == ids.photos.sorted(by: uuidOrder))
        #expect(f.track.corners.map(\.id) == ids.corners && f.track.points.map(\.id) == ids.points)
        f.failure.enabled = false
        try f.imu.stopAndFlush()
        f.clock.wall = 4000
        try await f.coordinator.stop()
        #expect(try f.samples().count == 1)
        for photo in f.track.photos {
            let bytes = try f.photos.read(relativePath: photo.filePath)
            #expect(SHA256.hash(data: bytes) == SHA256.hash(data: f.jpeg))
        }
        #expect(try NodePhotoAssociation.photo(for: #require(f.track.tags.first { $0.isNode })).tagID != nil)
    }

    @Test("Deleting a disposable Track cascades IMU batches as well as existing evidence")
    func cascade() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        _ = try f.addEvidence()
        f.emit(.accelerometer, at: 102)
        f.clock.wall = 4000
        try await f.coordinator.stop()
        #expect(f.track.imuBatches.count == 1)
        try f.coordinator.delete(f.track)
        #expect(try f.context.fetch(FetchDescriptor<TrackIMUBatch>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<Track>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackSegment>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackCorner>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("photos/\(f.track.id.uuidString.lowercased())").path))
    }

    @Test("Area deletion does not delete raw IMU or segment data")
    func areaDeletion() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let area = Area(name: "Synthetic", createdAt: 1)
        f.context.insert(area)
        try f.context.save()
        f.emit(.accelerometer, at: 101)
        try f.imu.stopAndFlush()
        try Phase2DataStore(context: f.context).deleteAreaPreservingContents(area)
        #expect(try f.samples().count == 1 && f.track.segments.count == 1)
    }

    @Test("Persistence rejects wrong segment, nonfinite values and oversized batches", arguments: ["segment", "nonfinite", "oversized"])
    func persistenceValidation(_ defect: String) throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let segment = try #require(f.coordinator.activeSegment?.id)
        let sample = f.sample(segment: defect == "segment" ? UUID() : segment, x: defect == "nonfinite" ? .nan : 1)
        let values = defect == "oversized" ? Array(repeating: sample, count: 101) : [sample]
        #expect(throws: (any Error).self) {
            try f.store.saveIMU(id: UUID(), samples: values, status: .init(), for: f.track)
        }
        #expect(f.track.imuBatches.isEmpty && !f.context.hasChanges)
    }

    @Test("Repeated persisted times and conflicting batch IDs are rejected")
    func persistenceIdempotency() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let sample = f.sample(segment: try #require(f.coordinator.activeSegment?.id))
        let id = UUID()
        try f.store.saveIMU(id: id, samples: [sample], status: .init(), for: f.track)
        try f.store.saveIMU(id: id, samples: [sample], status: .init(), for: f.track)
        #expect(throws: RawIMUError.invalidBatch) {
            try f.store.saveIMU(id: UUID(), samples: [sample], status: .init(), for: f.track)
        }
        #expect(throws: RawIMUError.invalidBatch) {
            try f.store.saveIMU(id: id, samples: [], status: .init(), for: f.track)
        }
        #expect(f.track.imuBatches.count == 1)
    }

    @Test("Decoded payload corruption is explicit, never substituted with zeroes")
    func corruptPayload() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 101)
        try f.imu.stopAndFlush()
        let batch = try #require(f.track.imuBatches.first)
        batch.sampleCount += 1
        #expect(throws: RawIMUError.invalidBatch) { try batch.decodedSamples() }
        batch.payload = Data("bad".utf8)
        #expect(throws: (any Error).self) { try batch.decodedSamples() }
    }

    @Test("V2 export refuses raw metadata even when other v3 flags are absent", arguments: ["intent", "interval", "state", "rejected", "batch"])
    func exportGate(_ defect: String) throws {
        let f = try Stage4Fixture(enabled: false)
        defer { f.dispose() }
        let legacy = Track(name: "Synthetic legacy", startedAt: 1)
        f.context.insert(legacy)
        switch defect {
        case "intent": legacy.rawIMURequested = true
        case "interval": legacy.rawIMUInterval = 0.02
        case "state": legacy.rawAccelState = "unsupported"
        case "rejected": legacy.rawIMURejectedCount = 1
        default:
            let sample = f.sample(segment: UUID())
            let batch = TrackIMUBatch(id: UUID(), samples: [sample], payload: try JSONEncoder().encode([sample]))
            f.context.insert(batch)
            batch.track = legacy
        }
        try f.context.save()
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: f.photos).buildUnassigned(tracks: [legacy], exportedAt: 5000)
        }
    }

    @Test("A legacy Track with no raw fields still exports via existing v2")
    func legacyExport() throws {
        let f = try Stage4Fixture(enabled: false)
        defer { f.dispose() }
        let legacy = Track(name: "Synthetic legacy", startedAt: 1, endedAt: 2)
        f.context.insert(legacy)
        try f.context.save()
        let result = try AreaExportSnapshotBuilder(photoStorage: f.photos).buildUnassigned(tracks: [legacy], exportedAt: 5000)
        #expect(result.tracks.count == 1 && result.tracks.first?.id == legacy.id)
    }

    private func uuidOrder(_ a: UUID, _ b: UUID) -> Bool { a.uuidString < b.uuidString }
}

enum Stage4Failure: Error, Equatable { case save }
@MainActor final class Stage4SaveFailure { var enabled = false; var afterCommit = false }
@MainActor final class Stage4Clock { var wall: Int64 = 1000; var uptime: Double = 100 }

@MainActor
final class Stage4FakeIMU: RawIMUServicing {
    typealias Handler = @MainActor @Sendable (RawIMUEvent) -> Void
    var starts = 0
    var stops = 0
    var intervals: [Double] = []
    var handlers: [Handler] = []
    var handler: Handler?
    var initialState: RawIMUChannelState = .waiting
    func start(interval: TimeInterval, handler: @escaping Handler) {
        starts += 1
        intervals.append(interval)
        self.handler = handler
        handlers.append(handler)
        handler(.state(.accelerometer, initialState))
        handler(.state(.gyroscope, initialState))
    }
    func stop() { stops += 1; handler = nil }
    func emit(_ event: RawIMUEvent) { handler?(event) }
    func emitOld(_ event: RawIMUEvent, index: Int) { handlers[index](event) }
}

@MainActor
final class Stage4Hub: SensorHubProtocol {
    var state = LiveSensorState.waiting
    var consumers: Set<SensorConsumer> = []
    var starts = 0
    var activeConsumerCount: Int { consumers.count }
    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) { starts += 1; consumers.insert(consumer) }
    func stop(consumer: SensorConsumer) { consumers.remove(consumer) }
    func requestLocationAuthorization() {}
}

@MainActor
final class Stage4Ticker: RecordingTicking {
    var starts = 0
    var handler: Handler?
    func start(handler: @escaping Handler) { starts += 1; self.handler = handler }
    func stop() async { handler = nil }
    func fire(_ time: Int64) async {
        guard let handler else { return }
        if !(await handler(time)) { self.handler = nil }
    }
}

@MainActor
final class Stage4Fixture {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let failure = Stage4SaveFailure()
    let clock = Stage4Clock()
    let service = Stage4FakeIMU()
    let hub = Stage4Hub()
    let ticker = Stage4Ticker()
    let store: SwiftDataRecordingStore
    let imu: RawIMURecorder
    let coordinator: RecordingCoordinator
    let track: Track
    let root: URL
    let photos: LocalPhotoFileStore
    let jpeg: Data

    init(enabled: Bool = true, channelState: RawIMUChannelState = .waiting) throws {
        container = try RoomMarkerModelContainer.make(inMemory: true)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage4Fixture-\(UUID())")
        photos = try LocalPhotoFileStore(rootURL: root)
        let failure = failure, clock = clock
        store = SwiftDataRecordingStore(context: container.mainContext) {
            if failure.enabled { throw Stage4Failure.save }
            try $0.save()
            if failure.afterCommit { throw Stage4Failure.save }
        }
        service.initialState = channelState
        imu = RawIMURecorder(service: service, persistence: store, now: { clock.wall }, uptime: { clock.uptime })
        coordinator = RecordingCoordinator(hub: hub, ticker: ticker, persistence: store,
                                           mediaPersistence: store, photoStorage: photos, rawIMU: imu,
                                           nowMilliseconds: { clock.wall })
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        try coordinator.start(name: "Synthetic Stage 4", collectRawIMU: enabled)
        track = try #require(coordinator.activeTrack)
    }

    func emit(_ kind: RawIMUKind, at time: Double, x: Double = 1, y: Double = 2, z: Double = 3) {
        clock.uptime = max(clock.uptime, time)
        service.emit(.reading(.init(kind: kind, sensorTimeSeconds: time, x: x, y: y, z: z)))
    }
    func sample(segment: UUID, x: Double = 1) -> RawIMUSample {
        .init(kind: .accelerometer, sensorTimeSeconds: 101, timeMs: 2000, receivedAtMs: 2000,
              segmentID: segment, x: x, y: 2, z: 3)
    }
    func samples() throws -> [RawIMUSample] {
        try track.imuBatches.sorted { $0.firstTimeMs < $1.firstTimeMs }.flatMap { try $0.decodedSamples() }
    }
    func addEvidence() throws -> (tags: [UUID], photos: [UUID], corners: [UUID], points: [UUID]) {
        clock.wall = 1500
        _ = try coordinator.captureCorner(note: "Synthetic turn")
        let capture = try #require(try coordinator.freezePhotoCapture(.success(jpegData: jpeg, capturedAt: 1500)))
        _ = try coordinator.saveNode(capture: capture, type: .door, note: "Synthetic node", area: nil, floor: "B1")
        let legacyPath = try photos.storeJPEG(jpeg, trackID: track.id, timeMs: 1600)
        context.insert(TrackTag(track: track, timeMs: 1600, tagType: .stairs, createdAt: 1600))
        context.insert(TrackPhoto(track: track, timeMs: 1600, filePath: legacyPath, createdAt: 1600))
        var point = SampleAssembler().assemble(timeMs: 1700, state: .waiting)
        point.segmentID = coordinator.activeSegment?.id
        try context.save()
        try photos.confirmReferenced(relativePath: legacyPath)
        try store.append([point], to: track)
        return (track.tags.map(\.id), track.photos.map(\.id), track.corners.map(\.id), track.points.map(\.id))
    }
    func dispose() { try? FileManager.default.removeItem(at: root) }
}
