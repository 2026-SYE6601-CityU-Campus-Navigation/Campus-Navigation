import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Full parity post-recording structure editing", .serialized)
@MainActor
struct FullParityStructureEditingTests {
    @Test("Split and merge reassign all segment evidence without changing measurements")
    func splitAndMerge() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let track = Track(name: "Synthetic", startedAt: 1_000, endedAt: 3_000,
                          isGlobalRecording: true)
        track.isSegmentedRecording = true
        let first = TrackSegment(track: track, ordinal: 0, startedAt: 1_000,
                                 endedAt: 2_000, environment: .indoor)
        let second = TrackSegment(track: track, ordinal: 1, startedAt: 2_000,
                                  endedAt: 3_000, environment: .outdoor)
        let boundary = TrackTag(track: track, timeMs: 1_500, tagType: .door, note: "Boundary",
                                createdAt: 1_500, recordKindRawValue: "node")
        let early = TrackPoint(track: track, timeMs: 1_250, latitude: 22.3,
                               longitude: 114.1, segmentID: first.id)
        let late = TrackPoint(track: track, timeMs: 1_750, latitude: 22.3001,
                              longitude: 114.1001, segmentID: first.id)
        let cornerDraft = TrackPointDraft(timeMs: 1_800, latitude: 22.3002, longitude: 114.1002,
                                          altitude: 12, accuracy: 3, pressureHpa: 1_008,
                                          magneticX: 1, magneticY: 2, magneticZ: 3,
                                          headingDeg: 90, wifiAvailability: .unsupported,
                                          wifiCount: nil, wifiTop: nil,
                                          segmentID: first.id)
        let corner = TrackCorner(track: track, sample: cornerDraft, note: "turn")
        let samples = [
            RawIMUSample(kind: .accelerometer, sensorTimeSeconds: 10, timeMs: 1_300,
                         receivedAtMs: 1_301, segmentID: first.id, x: 1, y: 2, z: 3),
            RawIMUSample(kind: .gyroscope, sensorTimeSeconds: 11, timeMs: 1_900,
                         receivedAtMs: 1_901, segmentID: first.id, x: 4, y: 5, z: 6),
        ]
        let batch = TrackIMUBatch(id: UUID(), samples: samples,
                                  payload: try JSONEncoder().encode(samples))
        batch.track = track
        for model in [track as any PersistentModel, first, second, boundary, early, late, corner, batch] {
            context.insert(model)
        }
        try context.save()

        let editor = TrackStructureEditor(context: context)
        let replacement = try editor.split(first, at: boundary, newEnvironment: .unknown, in: track)
        #expect(TrackSegmentRules.ordered(in: track).map(\.ordinal) == [0, 1, 2])
        #expect(first.endedAt == 1_500 && replacement.startedAt == 1_500 && replacement.endedAt == 2_000)
        #expect(early.segmentID == first.id && late.segmentID == replacement.id)
        #expect(corner.segmentID == replacement.id)
        let splitSamples = try batch.decodedSamples()
        #expect(splitSamples[0].segmentID == first.id && splitSamples[1].segmentID == replacement.id)
        #expect(splitSamples.map { [$0.x, $0.y, $0.z] } == [[1, 2, 3], [4, 5, 6]])

        try editor.mergeIntoPrevious(replacement, in: track)
        #expect(TrackSegmentRules.ordered(in: track).map(\.ordinal) == [0, 1])
        #expect(first.endedAt == 2_000 && late.segmentID == first.id && corner.segmentID == first.id)
        #expect(try batch.decodedSamples().allSatisfy { $0.segmentID == first.id })
        #expect(track.points.count == 2 && track.corners.count == 1 && track.imuBatches.count == 1)
    }

    @Test("Environment correction requires a completed valid segmented track")
    func environmentCorrection() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let track = Track(name: "Synthetic", startedAt: 1_000, endedAt: 2_000)
        track.isSegmentedRecording = true
        let segment = TrackSegment(track: track, ordinal: 0, startedAt: 1_000,
                                   endedAt: 2_000, environment: .unknown)
        context.insert(track); context.insert(segment); try context.save()
        try TrackStructureEditor(context: context).setEnvironment(.indoor, for: segment, in: track)
        #expect(segment.environment == .indoor)
        track.endedAt = nil
        #expect(throws: TrackStructureEditingError.activeOrIncompleteTrack) {
            try TrackStructureEditor(context: context).setEnvironment(.outdoor, for: segment, in: track)
        }
        #expect(segment.environment == .indoor)
    }
}
