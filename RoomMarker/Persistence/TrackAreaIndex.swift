import Foundation

/// Current membership comes from explicit tag assignments, never legacy Track.area.
enum TrackAreaIndex {
    static func tracks(in areaID: UUID, from tracks: [Track]) -> [Track] {
        unique(tracks.filter { track in
            track.tags.contains {
                $0.areaStateRawValue == "assigned" && $0.areaID == areaID
            }
        })
    }

    static func unassigned(in tracks: [Track]) -> [Track] {
        unique(tracks.filter { track in
            track.tags.contains {
                $0.areaStateRawValue == "unassigned" && $0.areaID == nil
            }
        })
    }

    /// Transitional v2 export must see all current members before rejecting rich data.
    static func unassignedV2ExportCandidates(in tracks: [Track]) -> [Track] {
        unique(tracks.filter { !$0.isGlobalRecording && $0.area == nil } + unassigned(in: tracks))
    }

    static func areaLabel(for tag: TrackTag, areas: [Area]) -> String {
        switch tag.areaStateRawValue {
        case "assigned":
            areas.first { $0.id == tag.areaID }?.name ?? "区域已不可用"
        case "unassigned":
            "未分区"
        default:
            "区域未知（历史标签）"
        }
    }

    private static func unique(_ tracks: [Track]) -> [Track] {
        var seen = Set<UUID>()
        return tracks.filter { seen.insert($0.id).inserted }
    }
}
