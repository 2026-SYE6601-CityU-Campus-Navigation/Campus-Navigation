import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import RoomMarker

@Suite("Stage 3 corners and environment segments", .serialized)
@MainActor
struct Stage3StructureTests {
    @Test("Track and first segment persist together", arguments: TrackEnvironment.allCases)
    func initialEnvironment(_ environment: TrackEnvironment) throws {
        let f = try Stage3Fixture(environment: environment)
        defer { f.dispose() }
        let segment = try #require(f.coordinator.activeSegment)
        #expect(f.track.isSegmentedRecording && f.track.isGlobalRecording && f.track.area == nil)
        #expect(segment.ordinal == 0 && segment.startedAt == 1000 && segment.endedAt == nil)
        #expect(segment.environment == environment && segment.track?.id == f.track.id)
        #expect(try f.context.fetch(FetchDescriptor<TrackSegment>()).count == 1)
    }

    @Test("Default environment is explicitly unknown, never guessed indoor")
    func defaultUnknown() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        #expect(f.coordinator.activeSegment?.environment == .unknown)
    }

    @Test("Switch commits the old tail and assigns later points to the new segment")
    func switchWithTail() async throws {
        let f = try Stage3Fixture(environment: .indoor)
        defer { f.dispose() }
        let firstID = try #require(f.coordinator.activeSegment?.id)
        await f.tick(2000)
        await f.tick(3000)
        f.clock.value = 3500
        try f.coordinator.changeEnvironment(to: .outdoor)
        let secondID = try #require(f.coordinator.activeSegment?.id)
        #expect(f.track.points.count == 2)
        #expect(f.track.points.allSatisfy { $0.segmentID == firstID })
        #expect(f.track.segments.first { $0.id == firstID }?.endedAt == 3500)
        await f.tick(4000)
        f.clock.value = 5000
        try await f.coordinator.stop()
        let point = try #require(f.track.points.first { $0.timeMs == 4000 })
        #expect(point.segmentID == secondID)
        #expect(f.track.points.count == 3 && f.track.endedAt == 5000)
        #expect(f.track.segments.first { $0.id == secondID }?.endedAt == 5000)
    }

    @Test("Selecting the same environment does not create a boundary or flush")
    func sameEnvironment() async throws {
        let f = try Stage3Fixture(environment: .indoor)
        defer { f.dispose() }
        await f.tick(2000)
        try f.coordinator.changeEnvironment(to: .indoor)
        #expect(f.track.segments.count == 1 && f.track.points.isEmpty)
        #expect(f.coordinator.currentSampleCount == 1)
    }

    @Test("Indoor/outdoor/unknown cycles have stable ordered contiguous boundaries")
    func repeatedSwitches() throws {
        let f = try Stage3Fixture(environment: .indoor)
        defer { f.dispose() }
        for (time, environment) in [(2000, TrackEnvironment.outdoor), (3000, .unknown), (4000, .indoor)] {
            f.clock.value = Int64(time)
            try f.coordinator.changeEnvironment(to: environment)
        }
        let segments = TrackSegmentRules.ordered(in: f.track)
        #expect(segments.map(\.ordinal) == [0, 1, 2, 3])
        #expect(segments.map(\.environmentRawValue) == ["indoor", "outdoor", "unknown", "indoor"])
        #expect(segments.map(\.startedAt) == [1000, 2000, 3000, 4000])
        #expect(segments.map(\.endedAt) == [2000, 3000, 4000, nil])
        #expect(Set(segments.map(\.id)).count == 4)
    }

    @Test("Switch save failure rolls back boundary and tail; retry persists each point once")
    func switchFailureAndRetry() async throws {
        let f = try Stage3Fixture(environment: .indoor)
        defer { f.dispose() }
        let firstID = try #require(f.coordinator.activeSegment?.id)
        await f.tick(2000)
        await f.tick(3000)
        f.clock.value = 3500
        f.failure.enabled = true
        #expect(throws: Stage3Failure.save) { try f.coordinator.changeEnvironment(to: .outdoor) }
        #expect(f.track.points.isEmpty && f.track.segments.count == 1)
        #expect(f.coordinator.activeSegment?.id == firstID && f.coordinator.activeSegment?.endedAt == nil)
        #expect(f.coordinator.currentSampleCount == 2 && f.coordinator.isRecording)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackSegment>()).count == 1)
        f.failure.enabled = false
        try f.coordinator.changeEnvironment(to: .outdoor)
        #expect(f.track.points.map(\.timeMs).sorted() == [2000, 3000])
        #expect(f.track.points.allSatisfy { $0.segmentID == firstID })
        #expect(f.track.segments.count == 2 && f.ticker.starts == 1 && f.hub.starts == 1)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).count == 2)
        #expect(try f.context.fetch(FetchDescriptor<TrackSegment>()).count == 2)
    }

    @Test("Boundary rollback retains already committed points, corner and node-photo evidence")
    func switchFailurePreservesExistingGraph() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        for time in [Int64(2000), 3000, 4000, 5000, 6000] { await f.tick(time) }
        f.clock.value = 6500
        let corner = try f.coordinator.captureCorner()
        let node = try f.coordinator.saveNode(capture: f.capture(), type: .door, note: "", area: nil, floor: "")
        let photo = try NodePhotoAssociation.photo(for: node)
        let pointIDs = Set(f.track.points.map(\.id))
        await f.tick(7000)
        f.clock.value = 7500
        f.failure.enabled = true
        #expect(throws: Stage3Failure.save) { try f.coordinator.changeEnvironment(to: .indoor) }
        #expect(Set(f.track.points.map(\.id)) == pointIDs && f.track.points.count == 5)
        #expect(f.track.corners.map(\.id) == [corner.id])
        #expect(f.track.tags.map(\.id) == [node.id] && f.track.photos.map(\.id) == [photo.id])
        #expect(try f.photos.read(relativePath: photo.filePath) == f.jpeg)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).count == 5)
        #expect(try f.context.fetch(FetchDescriptor<TrackSegment>()).count == 1)
        f.failure.enabled = false
        try f.coordinator.changeEnvironment(to: .indoor)
        #expect(f.track.points.count == 6 && Set(f.track.points.map(\.id)).isSuperset(of: pointIDs))
        #expect(f.track.corners.map(\.id) == [corner.id])
    }

    @Test("Periodic batch failure removes uncommitted inverse entries, permitting exact retry")
    func pointBatchRollback() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        var sample = SampleAssembler().assemble(timeMs: 2000, state: .waiting)
        sample.segmentID = f.coordinator.activeSegment?.id
        f.failure.enabled = true
        #expect(throws: Stage3Failure.save) { try f.store.append([sample], to: f.track) }
        #expect(f.track.points.isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).isEmpty)
        f.failure.enabled = false
        try f.store.append([sample], to: f.track)
        #expect(f.track.points.count == 1)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).count == 1)
    }

    @Test("Failed initial segment commit leaves neither a Track nor a segment")
    func startFailure() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataRecordingStore(context: context) { _ in throw Stage3Failure.save }
        #expect(throws: Stage3Failure.save) {
            try store.createSegmentedTrack(name: "Synthetic", startedAt: 1000, environment: .unknown)
        }
        #expect(try context.fetch(FetchDescriptor<Track>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrackSegment>()).isEmpty)
    }

    @Test("Corner freezes the available synthetic snapshot without adding a periodic point or photo")
    func fullCorner() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.hub.state = fullState()
        f.clock.value = 2000
        let corner = try f.coordinator.captureCorner(note: "  turn  ")
        f.hub.state = .waiting
        #expect(corner.timeMs == 2000 && corner.note == "turn")
        #expect(corner.latitude == 0 && corner.longitude == 0 && corner.altitude == 12)
        #expect(corner.accuracy == 3 && corner.pressureHpa == 1008)
        #expect(corner.headingDeg == 90 && corner.magneticX == 1 && corner.magneticY == 2 && corner.magneticZ == 3)
        #expect(corner.segmentID == f.coordinator.activeSegment?.id && corner.track?.id == f.track.id)
        #expect(f.track.points.isEmpty && f.track.tags.isEmpty && f.track.photos.isEmpty)
        #expect(f.coordinator.currentSampleCount == 0 && f.coordinator.isRecording)
    }

    @Test("No hardware readings still permits a real manual corner with nil values")
    func cornerWithoutReadings() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 2000
        let corner = try f.coordinator.captureCorner()
        #expect(corner.latitude == nil && corner.longitude == nil && corner.altitude == nil)
        #expect(corner.accuracy == nil && corner.pressureHpa == nil && corner.headingDeg == nil)
        #expect(corner.magneticX == nil && corner.magneticY == nil && corner.magneticZ == nil)
    }

    @Test("Nonfinite and negative-invalid measurements are not fabricated as zero")
    func invalidCornerReadings() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.hub.state = LiveSensorState(
            permission: .denied,
            location: available(LocationReading(latitude: .nan, longitude: .infinity,
                                                altitude: .nan, horizontalAccuracy: -1)),
            pressureHpa: available(-1), magneticField: available(MagneticFieldReading(x: .nan, y: .infinity, z: -.infinity)),
            headingDeg: available(.nan)
        )
        f.clock.value = 2000
        let corner = try f.coordinator.captureCorner()
        #expect(corner.latitude == nil && corner.longitude == nil && corner.accuracy == nil)
        #expect(corner.pressureHpa == nil && corner.headingDeg == nil && corner.magneticX == nil)
    }

    @Test("Stale location and heading are omitted from corner evidence")
    func staleCornerReadings() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.hub.state.location = .stale(TimestampedSensorValue(
            value: LocationReading(latitude: 0, longitude: 0, altitude: 12, horizontalAccuracy: 3),
            capturedAt: Date(timeIntervalSince1970: 0)
        ))
        f.hub.state.headingDeg = .stale(TimestampedSensorValue(value: 90, capturedAt: Date(timeIntervalSince1970: 0)))
        f.clock.value = 2000
        let corner = try f.coordinator.captureCorner()
        #expect(corner.latitude == nil && corner.headingDeg == nil)
    }

    @Test("Corner save failure preserves existing evidence and recording")
    func cornerFailure() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 2000
        f.failure.enabled = true
        #expect(throws: Stage3Failure.save) { try f.coordinator.captureCorner() }
        #expect(f.track.corners.isEmpty && f.track.segments.count == 1 && f.coordinator.isRecording)
        #expect(try f.context.fetch(FetchDescriptor<TrackCorner>()).isEmpty)
        f.failure.enabled = false
        _ = try f.coordinator.captureCorner()
        #expect(f.track.corners.count == 1)
        #expect(try f.context.fetch(FetchDescriptor<TrackCorner>()).count == 1)
    }

    @Test("Repeated same-millisecond corner press is rejected, not duplicated")
    func duplicateCorner() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 2000
        _ = try f.coordinator.captureCorner()
        #expect(throws: TrackStructureError.duplicateCorner) { try f.coordinator.captureCorner() }
        #expect(f.track.corners.count == 1)
    }

    @Test("Backward clock cannot create a corner behind existing evidence")
    func backwardCornerTime() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        await f.tick(3000)
        f.clock.value = 2000
        #expect(throws: TrackStructureError.invalidTimestamp) { try f.coordinator.captureCorner() }
        #expect(f.track.corners.isEmpty)
    }

    @Test("Boundary cannot reclassify an already accepted timestamp")
    func boundaryAtPointRejected() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        await f.tick(2000)
        #expect(throws: TrackStructureError.invalidTimestamp) { try f.coordinator.changeEnvironment(to: .outdoor) }
        #expect(f.track.segments.count == 1 && f.coordinator.currentSampleCount == 1)
    }

    @Test("Boundary cannot precede an existing corner")
    func boundaryAtCornerRejected() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 3000
        _ = try f.coordinator.captureCorner()
        f.clock.value = 2500
        #expect(throws: TrackStructureError.invalidTimestamp) { try f.coordinator.changeEnvironment(to: .indoor) }
        #expect(f.track.segments.count == 1)
    }

    @Test("Delayed pre-boundary ticks are ignored; exact boundary belongs to new segment")
    func boundaryTickAssignment() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 3000
        try f.coordinator.changeEnvironment(to: .outdoor)
        await f.tick(2500)
        #expect(f.coordinator.currentSampleCount == 0)
        await f.tick(3000)
        f.clock.value = 4000
        let secondID = try #require(f.coordinator.activeSegment?.id)
        try await f.coordinator.stop()
        #expect(f.track.points.count == 1 && f.track.points.first?.timeMs == 3000)
        #expect(f.track.points.first?.segmentID == secondID)
    }

    @Test("Stop flushes the final tail and closes the last segment at actual endedAt")
    func stopClosesSegment() async throws {
        let f = try Stage3Fixture(environment: .outdoor)
        defer { f.dispose() }
        await f.tick(2000)
        await f.tick(3000)
        f.clock.value = 3500
        _ = try f.coordinator.captureCorner()
        f.clock.value = 4000
        try await f.coordinator.stop()
        #expect(f.track.points.count == 2 && f.track.corners.count == 1)
        #expect(f.track.segments.first?.endedAt == 4000 && f.track.endedAt == 4000)
        #expect(f.coordinator.state == .idle && f.hub.activeConsumerCount == 0)
    }

    @Test("Failed stop leaves segment open and can only close by explicit recovery")
    func failedStopAndRecovery() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 2000
        f.failure.enabled = true
        do {
            try await f.coordinator.stop()
            Issue.record("Expected save failure")
        } catch {}
        #expect(f.track.endedAt == nil && f.track.segments.first?.endedAt == nil)
        f.failure.enabled = false
        await f.coordinator.resetFailure()
        f.clock.value = 3000
        try f.coordinator.finalizeInterrupted(f.track)
        #expect(f.track.endedAt == 3000 && f.track.segments.first?.endedAt == 3000)
        #expect(f.track.points.isEmpty)
    }

    @Test("Backward stop time fails rather than inventing a terminal boundary")
    func invalidStopTime() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        await f.tick(3000)
        f.clock.value = 2000
        do {
            try await f.coordinator.stop()
            Issue.record("Expected timestamp rejection")
        } catch {
            #expect(error as? TrackStructureError == .invalidTimestamp)
        }
        #expect(f.track.points.count == 1)
        #expect(f.track.endedAt == nil && f.track.segments.first?.endedAt == nil)
    }

    @Test("Background and lock-like gaps do not split segments or synthesize catch-up points")
    func realSchedulingGap() async throws {
        let f = try Stage3Fixture(environment: .indoor)
        defer { f.dispose() }
        await f.tick(2000)
        f.coordinator.handleLifecycleTransition(.background)
        f.coordinator.handleLifecycleTransition(.active)
        await f.tick(62000)
        f.clock.value = 63000
        try await f.coordinator.stop()
        #expect(f.track.points.map(\.timeMs).sorted() == [2000, 62000])
        #expect(f.track.segments.count == 1 && f.ticker.starts == 1 && f.hub.starts == 1)
    }

    @Test("Inactive and finalized Tracks reject capture, switch and point append")
    func finalizedRejectsChanges() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 2000
        try await f.coordinator.stop()
        #expect(throws: TrackMediaError.noActiveTrack) { try f.coordinator.captureCorner() }
        #expect(throws: TrackMediaError.noActiveTrack) { try f.coordinator.changeEnvironment(to: .indoor) }
        #expect(throws: RecordingError.finalizedTrack) { try f.store.append([], to: f.track) }
        #expect(f.track.segments.count == 1)
    }

    @Test("Environment switch preserves frozen node/photo IDs, relation and JPEG bytes")
    func nodePhotoPreserved() throws {
        let f = try Stage3Fixture(environment: .indoor)
        defer { f.dispose() }
        f.clock.value = 2000
        let capture = try f.capture()
        f.clock.value = 3000
        try f.coordinator.changeEnvironment(to: .outdoor)
        let tag = try f.coordinator.saveNode(capture: capture, type: .door, note: "node", area: nil, floor: "B1")
        let photo = try NodePhotoAssociation.photo(for: tag)
        let id = photo.id
        f.clock.value = 4000
        try f.coordinator.changeEnvironment(to: .indoor)
        #expect(photo.id == id && photo.tagID == tag.id && tag.timeMs == 2000 && photo.timeMs == 2000)
        #expect(tag.floor == "B1" && f.track.tags.count == 1 && f.track.photos.count == 1)
        #expect(SHA256.hash(data: try f.photos.read(relativePath: photo.filePath)) == SHA256.hash(data: f.jpeg))
    }

    @Test("Deleting a corner preserves periodic points, nodes, photos and segments")
    func deleteCornerOnly() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        await f.tick(2000)
        f.clock.value = 2500
        let corner = try f.coordinator.captureCorner()
        let tag = try f.coordinator.saveNode(capture: f.capture(), type: .stairs, note: "", area: nil, floor: "")
        let photo = try NodePhotoAssociation.photo(for: tag)
        f.coordinator.handleLifecycleTransition(.background)
        try f.coordinator.deleteCorner(corner)
        #expect(f.track.corners.isEmpty && f.track.points.count == 1)
        #expect(f.track.tags.count == 1 && f.track.photos.count == 1 && f.track.segments.count == 1)
        #expect(try f.photos.read(relativePath: photo.filePath) == f.jpeg)
    }

    @Test("Corner deletion save failure rolls back only that operation")
    func deleteCornerFailure() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.clock.value = 2000
        let corner = try f.coordinator.captureCorner()
        f.failure.enabled = true
        #expect(throws: Stage3Failure.save) { try f.coordinator.deleteCorner(corner) }
        #expect(f.track.corners.count == 1 && f.track.corners.first?.id == corner.id)
    }

    @Test("Completed Track deletion cascades corners, segments, nodes, points and photo files")
    func trackCascade() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        let trackID = f.track.id
        await f.tick(2000)
        f.clock.value = 2500
        _ = try f.coordinator.captureCorner()
        _ = try f.coordinator.saveNode(capture: f.capture(), type: .door, note: "", area: nil, floor: "")
        f.clock.value = 3000
        try f.coordinator.changeEnvironment(to: .outdoor)
        f.clock.value = 4000
        try await f.coordinator.stop()
        try f.coordinator.delete(f.track)
        #expect(try f.context.fetch(FetchDescriptor<Track>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackSegment>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackCorner>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPoint>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackTag>()).isEmpty)
        #expect(try f.context.fetch(FetchDescriptor<TrackPhoto>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("photos/\(trackID.uuidString.lowercased())").path))
    }

    @Test("Area deletion does not cascade structure or node-photo evidence")
    func areaDeletion() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        let area = Area(name: "Synthetic Area", createdAt: 1)
        f.context.insert(area)
        try f.context.save()
        f.clock.value = 2000
        let node = try f.coordinator.saveNode(capture: f.capture(), type: .door, note: "", area: area, floor: "2/F")
        _ = try f.coordinator.captureCorner()
        try Phase2DataStore(context: f.context).deleteAreaPreservingContents(area)
        #expect(f.track.corners.count == 1 && f.track.segments.count == 1)
        #expect(node.areaID == nil && node.floor == "2/F")
        #expect(try NodePhotoAssociation.photo(for: node).tagID == node.id)
    }

    @Test("Corner cannot claim a different Track segment")
    func wrongCornerSegment() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        var sample = SampleAssembler().assemble(timeMs: 2000, state: .waiting)
        sample.segmentID = UUID()
        #expect(throws: TrackStructureError.wrongSegment) {
            try f.store.createCorner(sample: sample, note: "", for: f.track)
        }
        #expect(f.track.corners.isEmpty)
    }

    @Test("Periodic point append rejects mismatched or missing segment ID")
    func wrongPointSegment() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        var sample = SampleAssembler().assemble(timeMs: 2000, state: .waiting)
        #expect(throws: TrackStructureError.wrongSegment) { try f.store.append([sample], to: f.track) }
        sample.segmentID = UUID()
        #expect(throws: TrackStructureError.wrongSegment) { try f.store.append([sample], to: f.track) }
        #expect(f.track.points.isEmpty)
    }

    @Test("Malformed segment chain rejects new evidence", arguments: ["ordinal", "environment", "closed"])
    func corruptChain(_ defect: String) throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        let segment = try #require(f.coordinator.activeSegment)
        switch defect {
        case "ordinal": segment.ordinal = 2
        case "environment": segment.environmentRawValue = "fake"
        default: segment.endedAt = 2000
        }
        try f.context.save()
        f.clock.value = 3000
        #expect(throws: TrackStructureError.invalidSegments) { try f.coordinator.captureCorner() }
        #expect(f.track.corners.isEmpty)
    }

    @Test("Historical Track remains unsegmented with unknown point membership")
    func legacyRemainsUnsegmented() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        let legacy = try f.store.createTrack(name: "Historical", area: nil, startedAt: 1)
        try f.store.append([SampleAssembler().assemble(timeMs: 2, state: .waiting)], to: legacy)
        #expect(!legacy.isSegmentedRecording && legacy.segments.isEmpty && legacy.corners.isEmpty)
        #expect(legacy.points.first?.segmentID == nil)
        #expect(throws: TrackStructureError.unavailable) { try TrackSegmentRules.current(in: legacy) }
    }

    @Test("V2 gate rejects segmentation even after legacy/global flags are cleared")
    func exportGate() throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        f.track.isGlobalRecording = false
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: f.photos).buildUnassigned(tracks: [f.track], exportedAt: 5000)
        }
        f.track.isSegmentedRecording = false
        #expect(throws: ExportValidationError.requiresV3Export) {
            try AreaExportSnapshotBuilder(photoStorage: f.photos).buildUnassigned(tracks: [f.track], exportedAt: 5000)
        }
    }

    @Test("An immediate stop may close a zero-duration empty segment without invented time")
    func emptyImmediateStop() async throws {
        let f = try Stage3Fixture()
        defer { f.dispose() }
        try await f.coordinator.stop()
        #expect(f.track.startedAt == 1000 && f.track.endedAt == 1000)
        #expect(f.track.segments.first?.endedAt == 1000 && f.track.points.isEmpty)
    }

    private func fullState() -> LiveSensorState {
        LiveSensorState(permission: .authorizedWhenInUse,
                        location: available(LocationReading(latitude: 0, longitude: 0, altitude: 12, horizontalAccuracy: 3)),
                        pressureHpa: available(1008),
                        magneticField: available(MagneticFieldReading(x: 1, y: 2, z: 3)),
                        headingDeg: available(90))
    }

    private func available<T: Sendable>(_ value: T) -> SensorValueState<T> {
        .available(TimestampedSensorValue(value: value, capturedAt: Date()))
    }
}

private enum Stage3Failure: Error, Equatable { case save }

@MainActor
private final class Stage3SaveFailure { var enabled = false }

@MainActor
private final class Stage3Clock { var value: Int64 = 1000 }

@MainActor
private final class Stage3Fixture {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let failure = Stage3SaveFailure()
    let clock = Stage3Clock()
    let hub = Stage3Hub()
    let ticker = Stage3Ticker()
    let store: SwiftDataRecordingStore
    let coordinator: RecordingCoordinator
    let track: Track
    let root: URL
    let photos: LocalPhotoFileStore
    let jpeg: Data

    init(environment: TrackEnvironment = .unknown) throws {
        container = try RoomMarkerModelContainer.make(inMemory: true)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Stage3Fixture-\(UUID())")
        photos = try LocalPhotoFileStore(rootURL: root)
        let failure = failure
        store = SwiftDataRecordingStore(context: container.mainContext) {
            if failure.enabled { throw Stage3Failure.save }
            try $0.save()
        }
        let clock = clock
        coordinator = RecordingCoordinator(hub: hub, ticker: ticker, persistence: store,
                                           mediaPersistence: store, photoStorage: photos,
                                           nowMilliseconds: { clock.value })
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        }
        jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        try coordinator.start(name: "Synthetic Stage 3", environment: environment)
        track = try #require(coordinator.activeTrack)
    }

    func tick(_ time: Int64) async {
        clock.value = time
        await ticker.fire(time)
    }

    func capture() throws -> CapturedTrackPhoto {
        try #require(try coordinator.freezePhotoCapture(.success(jpegData: jpeg, capturedAt: clock.value)))
    }

    func dispose() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class Stage3Hub: SensorHubProtocol {
    var state = LiveSensorState.waiting
    var consumers: Set<SensorConsumer> = []
    var starts = 0
    var activeConsumerCount: Int { consumers.count }
    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) {
        starts += 1
        consumers.insert(consumer)
    }
    func stop(consumer: SensorConsumer) { consumers.remove(consumer) }
    func requestLocationAuthorization() {}
}

@MainActor
private final class Stage3Ticker: RecordingTicking {
    var starts = 0
    private var handler: Handler?
    func start(handler: @escaping Handler) {
        starts += 1
        self.handler = handler
    }
    func stop() async { handler = nil }
    func fire(_ time: Int64) async {
        guard let handler else { return }
        if !(await handler(time)) { self.handler = nil }
    }
}
