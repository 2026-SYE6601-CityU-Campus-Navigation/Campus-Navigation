import Foundation

nonisolated enum TrackEnvironment: String, Codable, CaseIterable, Sendable {
    case unknown
    case indoor
    case outdoor

    var title: String {
        switch self {
        case .unknown: "未知"
        case .indoor: "室内"
        case .outdoor: "室外"
        }
    }
}

enum TrackStructureError: LocalizedError, Equatable {
    case unavailable
    case invalidSegments
    case invalidTimestamp
    case duplicateCorner
    case wrongSegment

    var errorDescription: String? {
        switch self {
        case .unavailable: "这条轨迹不支持分段采集；不会改写历史数据。"
        case .invalidSegments: "轨迹分段关系不完整，操作已停止，请保留数据检查。"
        case .invalidTimestamp: "当前时间早于或等于已记录边界。请检查系统时间后重试，不会补造时间。"
        case .duplicateCorner: "此时间的拐点已采集，请勿重复点击。"
        case .wrongSegment: "采集记录与所属轨迹分段不一致，未保存。"
        }
    }
}

@MainActor
protocol TrackStructurePersisting: AnyObject {
    // Track and its first segment must be committed together.
    func createSegmentedTrack(name: String, startedAt: Int64, environment: TrackEnvironment, collectRawIMU: Bool) throws -> Track
    // Old-segment tail and both sides of the boundary share one DB commit.
    func switchSegment(
        for track: Track, to environment: TrackEnvironment, at timeMs: Int64,
        pendingPoints: [TrackPointDraft]
    ) throws -> TrackSegment
    func createCorner(sample: TrackPointDraft, note: String, for track: Track) throws -> TrackCorner
    func deleteCorner(_ corner: TrackCorner) throws
}

@MainActor
enum TrackSegmentRules {
    static func ordered(in track: Track) -> [TrackSegment] {
        track.segments.sorted { $0.ordinal < $1.ordinal }
    }

    static func current(in track: Track) throws -> TrackSegment {
        guard track.isSegmentedRecording else { throw TrackStructureError.unavailable }
        guard track.endedAt == nil else { throw RecordingError.finalizedTrack }
        let segments = ordered(in: track)
        guard let last = segments.last, segments.first?.startedAt == track.startedAt else {
            throw TrackStructureError.invalidSegments
        }
        for (index, segment) in segments.enumerated() {
            guard segment.ordinal == index, segment.track?.id == track.id, segment.environment != nil else {
                throw TrackStructureError.invalidSegments
            }
            if index + 1 < segments.count {
                guard segment.endedAt == segments[index + 1].startedAt,
                      segments[index + 1].startedAt > segment.startedAt else {
                    throw TrackStructureError.invalidSegments
                }
            } else if segment.endedAt != nil {
                throw TrackStructureError.invalidSegments
            }
        }
        return last
    }

    static func validate(_ sample: TrackPointDraft, in track: Track) throws {
        let segment = try current(in: track)
        guard sample.segmentID == segment.id, sample.timeMs >= segment.startedAt else {
            throw TrackStructureError.wrongSegment
        }
    }

    static func latestEvidenceTime(in track: Track, pending: [TrackPointDraft] = []) -> Int64 {
        ([track.startedAt] + track.points.map(\.timeMs) + track.corners.map(\.timeMs) +
         track.imuBatches.map(\.lastTimeMs) + pending.map(\.timeMs)).max()
            ?? track.startedAt
    }
}
