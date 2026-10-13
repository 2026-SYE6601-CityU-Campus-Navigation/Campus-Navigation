import Foundation
import Observation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Stage 6 offline recording readiness", .serialized)
@MainActor
struct Stage6OfflineTests {
    @Test("Sensor-rate counters do not invalidate views; all samples still reach persistence")
    func presentationIsNotSensorRate() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.accelerometer, at: 101)
        f.emit(.gyroscope, at: 101)
        let changes = Stage6ObservationCounter()
        withObservationTracking {
            _ = f.imu.acceptedCount
            _ = f.imu.lastReadings
            _ = f.imu.savedSummary
            _ = f.imu.pendingCount
            _ = f.imu.status
        } onChange: { changes.increment() }
        for index in 1...1000 {
            f.emit(index.isMultiple(of: 2) ? .accelerometer : .gyroscope, at: 101 + Double(index) * 0.02)
        }
        #expect(changes.count == 0)
        #expect(f.imu.acceptedCount == 1002 && f.imu.pendingCount == 2)
        #expect(f.imu.savedSummary.sampleCount == 1000 && f.imu.savedSummary.recentSamples.count == 4)
        f.clock.wall = 25000
        try await f.coordinator.stop()
        #expect(try f.samples().count == 1002 && f.imu.savedSummary.sampleCount == 1002)
    }

    @Test("Saved presentation counters advance only once after successful retry", arguments: [false, true])
    func summaryRetry(afterCommit: Bool) async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.failure.enabled = !afterCommit
        f.failure.afterCommit = afterCommit
        for index in 1...100 { f.emit(.accelerometer, at: 100 + Double(index) * 0.02) }
        #expect(f.imu.savedSummary.sampleCount == 0 && f.imu.pendingCount == 100)
        f.failure.enabled = false
        f.failure.afterCommit = false
        try f.imu.retry()
        try f.imu.retry()
        #expect(f.imu.savedSummary.accelerationCount == 100 && f.imu.savedSummary.gyroscopeCount == 0)
        #expect(f.track.imuBatches.count == 1 && f.imu.pendingCount == 0)
        f.clock.wall = 4000
        try await f.coordinator.stop()
        #expect(try RawIMUSavedSummary.read(f.track) == f.imu.savedSummary)
    }

    @Test("New recording resets presentation-only counters and preserves the previous Track")
    func summarySessionReset() async throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        f.emit(.gyroscope, at: 101)
        f.clock.wall = 3000
        try await f.coordinator.stop()
        #expect(f.imu.savedSummary.gyroscopeCount == 1)
        try f.coordinator.start(name: "Synthetic next", collectRawIMU: true)
        #expect(f.imu.savedSummary == RawIMUSavedSummary())
        #expect(try RawIMUSavedSummary.read(f.track).gyroscopeCount == 1)
        try await f.coordinator.stop()
    }

    @Test("Latest-time fetch is scoped to Track and channel, including a second persistence writer")
    func scopedLatestTimes() throws {
        let f = try Stage4Fixture()
        defer { f.dispose() }
        let segment = try #require(f.coordinator.activeSegment?.id)
        let other = try f.store.createSegmentedTrack(name: "Other", startedAt: 1000, environment: .indoor, collectRawIMU: true)
        let otherSegment = try #require(other.segments.first?.id)
        func sample(_ time: Double, _ kind: RawIMUKind, _ segment: UUID) -> RawIMUSample {
            .init(kind: kind, sensorTimeSeconds: time, timeMs: 2000, receivedAtMs: 2100,
                  segmentID: segment, x: 1, y: 2, z: 3)
        }
        try f.store.saveIMU(id: UUID(), samples: [sample(101, .accelerometer, segment)], status: .init(), for: f.track)
        try f.store.saveIMU(id: UUID(), samples: [sample(900, .accelerometer, otherSegment)], status: .init(), for: other)
        let secondWriter = SwiftDataRecordingStore(context: f.context)
        try secondWriter.saveIMU(id: UUID(), samples: [sample(103, .accelerometer, segment)], status: .init(), for: f.track)
        #expect(throws: RawIMUError.invalidBatch) {
            try f.store.saveIMU(id: UUID(), samples: [sample(102, .accelerometer, segment)], status: .init(), for: f.track)
        }
        try f.store.saveIMU(id: UUID(), samples: [sample(100.5, .gyroscope, segment)], status: .init(), for: f.track)
        #expect(f.track.imuBatches.count == 3 && other.imuBatches.count == 1)
    }

    @Test("Bounded point pages preserve every record, order and Track isolation")
    func pointPagination() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let track = Track(name: "Synthetic paged", startedAt: 0, endedAt: 300)
        let other = Track(name: "Other", startedAt: 0, endedAt: 300)
        context.insert(track)
        context.insert(other)
        for time in (1...205).reversed() { context.insert(TrackPoint(track: track, timeMs: Int64(time))) }
        context.insert(TrackPoint(track: other, timeMs: 50))
        try context.save()
        let pages = try (0...2).map { try TrackPointPage.load(trackID: track.id, page: $0, context: context) }
        #expect(pages.map(\.count) == [100, 100, 5])
        #expect(pages.flatMap { $0 }.map(\.timeMs) == (1...205).map(Int64.init))
        #expect(Set(pages.flatMap { $0 }.map(\.id)).count == 205)
        #expect(try TrackPointPage.load(trackID: track.id, page: 3, context: context).isEmpty)
        #expect(!context.hasChanges && track.points.count == 205)
        context.insert(TrackPoint(track: track, timeMs: 206))
        try context.save()
        #expect(try TrackPointPage.load(trackID: track.id, page: 2, context: context).map(\.timeMs) == Array(201...206).map(Int64.init))
        #expect(throws: TrackPointPage.Failure.invalidPage) { try TrackPointPage.load(trackID: track.id, page: -1, context: context) }
    }

    @Test("400000 synthetic IMU samples and original evidence survive v3 ZIP without truncation")
    func longArchive() async throws {
        let f = try await Stage5Fixture(complete: false)
        defer { f.dispose() }
        let segment = try #require(f.base.coordinator.activeSegment?.id)
        let originalPhotos = try f.originalPhotos()
        // SwiftData to-many relationships have no persisted array order.
        // Compare stable identity including multiplicity, not materialization order.
        let originalIDs = f.base.track.tags.map(\.id.uuidString).sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var sourcePayloads: [UUID: Data] = [:]
        // Existing four samples remain intact. This is an explicitly synthetic
        // export stress fixture, not injected device measurements or live Hz QA.
        for batchIndex in 0..<4000 {
            let samples = (0..<100).map { offset in
                let index = batchIndex * 100 + offset
                return RawIMUSample(kind: index.isMultiple(of: 2) ? .accelerometer : .gyroscope,
                    sensorTimeSeconds: 200 + Double(index) * 0.01, timeMs: 101000 + Int64(index) * 10,
                    receivedAtMs: 101050 + Int64(index) * 10, segmentID: segment,
                    x: Double(index % 7) / 10, y: -0.2, z: -1)
            }
            let batch = TrackIMUBatch(id: UUID(), samples: samples, payload: try encoder.encode(samples))
            f.base.context.insert(batch)
            batch.track = f.base.track
            sourcePayloads[batch.id] = batch.payload
        }
        try f.base.context.save()
        f.base.clock.wall = 4_200_000
        try await f.base.coordinator.stop()
        let start = ContinuousClock.now
        let snapshot = try f.builder.build(area: f.a, tracks: f.tracks(), areas: [f.a, f.b], exportedAt: 4_300_000)
        let staging = try f.staging.stage(snapshot, sessionID: UUID())
        let archive = try f.archive.createArchive(from: staging, areaName: "Synthetic long", exportedAt: 4_300_000)
        print("Stage6 synthetic 400004-sample snapshot/staging/ZIP: \(start.duration(to: .now))")
        let entries = try Stage5ZIP.read(archive.archiveURL)
        let manifest = try JSONDecoder().decode(ExportV3Manifest.self, from: #require(entries["manifest.json"]))
        let exported = try JSONDecoder().decode(ExportV3Track.self, from: #require(entries["tracks/\(f.id).json"]))
        #expect(manifest.trackCount == 1 && manifest.tracks.first?.counts == exported.counts)
        #expect(exported.counts.imuSampleCount == 400004 && exported.imu.sampleCount == 400004)
        #expect(exported.imu.accelerationCount == 200002 && exported.imu.gyroscopeCount == 200002)
        #expect(exported.imu.batches.count == 4001 && exported.tags.filter { $0.recordKind == "node" }.count == 2)
        #expect(exported.photos.count == 4 && exported.corners.count == 1 && exported.segments.count == 2)
        #expect(entries.keys.allSatisfy(ArchivePathValidator.isSafe))
        for photo in exported.photos { #expect(entries[photo.file] == originalPhotos[photo.file]) }
        for batch in exported.imu.batches {
            if let original = sourcePayloads[UUID(uuidString: batch.id)!] {
                let values = try JSONDecoder().decode([RawIMUSample].self, from: original)
                #expect(batch.samples.map(\.sensorTimeSeconds) == values.map(\.sensorTimeSeconds))
                #expect(batch.samples.map(\.timeMs) == values.map(\.timeMs))
                #expect(batch.samples.map(\.receivedAtMs) == values.map(\.receivedAtMs))
                #expect(batch.samples.map(\.x) == values.map(\.x))
            }
        }
        #expect(try f.originalPhotos() == originalPhotos)
        #expect(f.base.track.tags.map(\.id.uuidString).sorted() == originalIDs)
        #expect(f.base.track.imuBatches.allSatisfy { batch in
            sourcePayloads[batch.id].map { $0 == batch.payload } ?? true
        })
        #expect(!f.base.context.hasChanges)

        // Batch 4: keep every original stress assertion above, and compare the
        // bounded worker against that same 400004-sample reference (no downsizing).
        let preparation = V3ExportPreparation()
        let skeleton = try f.builder.build(area: f.a, tracks: f.tracks(), areas: [f.a, f.b],
            exportedAt: 4_300_000, preparation: preparation)
        let input = preparation.freeze(skeleton), root = f.stageRoot
        let config = f.archive.backgroundConfiguration
        let streamingStart = ContinuousClock.now
        let worker = Task.detached {
            let staged = try V3StreamingExporter.stage(input, base: root, sessionID: UUID())
            let zip = try config.service().createArchive(from: staged.staging, areaName: staged.name,
                exportedAt: staged.exportedAt)
            return (staged, zip)
        }
        // The task above cannot execute on MainActor; this actor remains available
        // while staging/ZIP is in flight. Physical UI latency is a separate check.
        await Task.yield()
        let (streamed, streamedZIP) = try await worker.value
        defer { try? f.staging.cleanUp(streamed.staging) }
        print("Batch4 synthetic 400004-sample streaming/ZIP: \(streamingStart.duration(to: .now))")
        let output = try JSONDecoder().decode(ExportV3Track.self, from: Data(contentsOf: #require(streamed.staging.trackURLs.first)))
        #expect(output == exported)
        #expect(streamed.metrics.encodedIMUSamples == 400004 && streamed.metrics.maxDecodedIMUSamples == 100)
        #expect(!streamed.metrics.ranOnMainThread && streamed.metrics.maxCopyChunkBytes <= 65536)
        #expect(streamedZIP.entryPaths.count == 7 && streamedZIP.entryPaths.contains("index.html"))
        #expect(try f.originalPhotos() == originalPhotos && !f.base.context.hasChanges)
    }
}

private nonisolated final class Stage6ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
