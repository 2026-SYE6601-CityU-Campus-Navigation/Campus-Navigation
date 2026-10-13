import Foundation
import SwiftData

enum TrackStructureEditingError: LocalizedError, Equatable {
    case activeOrIncompleteTrack
    case unavailableSegment
    case unavailableBoundary
    case invalidEvidence

    var errorDescription: String? {
        switch self {
        case .activeOrIncompleteTrack: "请先正常停止并保存轨迹，再修正环境分段。"
        case .unavailableSegment: "所选环境段已不可用，请重新打开轨迹。"
        case .unavailableBoundary: "请选择位于该段内部的节点作为分界。"
        case .invalidEvidence: "轨迹证据与分段不一致，未修改数据。"
        }
    }
}

@MainActor
final class TrackStructureEditor {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func setEnvironment(_ environment: TrackEnvironment, for segment: TrackSegment, in track: Track) throws {
        try validateCompleted(track)
        guard segment.track?.id == track.id, track.segments.contains(where: { $0.id == segment.id }) else {
            throw TrackStructureEditingError.unavailableSegment
        }
        segment.environmentRawValue = environment.rawValue
        try save()
    }

    @discardableResult
    func split(_ segment: TrackSegment, at tag: TrackTag, newEnvironment: TrackEnvironment,
               in track: Track) throws -> TrackSegment {
        try validateCompleted(track)
        guard tag.track?.id == track.id, tag.isNode else { throw TrackStructureEditingError.unavailableBoundary }
        let ordered = TrackSegmentRules.ordered(in: track)
        guard let index = ordered.firstIndex(where: { $0.id == segment.id }),
              let oldEnd = segment.endedAt,
              tag.timeMs > segment.startedAt, tag.timeMs < oldEnd else {
            throw TrackStructureEditingError.unavailableBoundary
        }

        let replacement = TrackSegment(track: nil, ordinal: segment.ordinal + 1,
                                       startedAt: tag.timeMs, endedAt: oldEnd,
                                       environment: newEnvironment)
        context.insert(replacement)
        replacement.track = track
        segment.endedAt = tag.timeMs
        for later in ordered[(index + 1)...].reversed() { later.ordinal += 1 }
        try moveEvidence(in: track, from: segment.id, to: replacement.id,
                         where: { $0 >= tag.timeMs })
        try save()
        return replacement
    }

    func mergeIntoPrevious(_ segment: TrackSegment, in track: Track) throws {
        try validateCompleted(track)
        let ordered = TrackSegmentRules.ordered(in: track)
        guard let index = ordered.firstIndex(where: { $0.id == segment.id }), index > 0 else {
            throw TrackStructureEditingError.unavailableSegment
        }
        let previous = ordered[index - 1]
        guard previous.endedAt == segment.startedAt else { throw TrackStructureEditingError.invalidEvidence }
        previous.endedAt = segment.endedAt
        try moveEvidence(in: track, from: segment.id, to: previous.id, where: { _ in true })
        context.delete(segment)
        for later in ordered[(index + 1)...] { later.ordinal -= 1 }
        try save()
    }

    private func validateCompleted(_ track: Track) throws {
        guard track.endedAt != nil, track.isSegmentedRecording else {
            throw TrackStructureEditingError.activeOrIncompleteTrack
        }
        let ordered = TrackSegmentRules.ordered(in: track)
        guard !ordered.isEmpty, ordered.first?.startedAt == track.startedAt,
              ordered.last?.endedAt == track.endedAt else { throw TrackStructureEditingError.invalidEvidence }
        for (index, segment) in ordered.enumerated() {
            guard segment.ordinal == index, segment.track?.id == track.id,
                  segment.environment != nil, let end = segment.endedAt, end > segment.startedAt else {
                throw TrackStructureEditingError.invalidEvidence
            }
            if index > 0, ordered[index - 1].endedAt != segment.startedAt {
                throw TrackStructureEditingError.invalidEvidence
            }
        }
    }

    private func moveEvidence(in track: Track, from oldID: UUID, to newID: UUID,
                              where shouldMove: (Int64) -> Bool) throws {
        for point in track.points where point.segmentID == oldID && shouldMove(point.timeMs) {
            point.segmentID = newID
        }
        for corner in track.corners where corner.segmentID == oldID && shouldMove(corner.timeMs) {
            corner.segmentID = newID
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for batch in track.imuBatches {
            let samples = try batch.decodedSamples()
            var changed = false
            let moved = samples.map { sample -> RawIMUSample in
                guard sample.segmentID == oldID, shouldMove(sample.timeMs) else { return sample }
                changed = true
                return RawIMUSample(kind: sample.kind, sensorTimeSeconds: sample.sensorTimeSeconds,
                                    timeMs: sample.timeMs, receivedAtMs: sample.receivedAtMs,
                                    segmentID: newID, x: sample.x, y: sample.y, z: sample.z)
            }
            if changed { batch.payload = try encoder.encode(moved) }
        }
    }

    private func save() throws {
        do {
            context.processPendingChanges()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
