import Foundation

enum RecordingLifecyclePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

enum RecordingElapsedTime {
    static func seconds(startedAt: Int64, now: Int64) -> Int64 {
        max(0, (now - startedAt) / 1_000)
    }
}

@MainActor
enum IncompleteTrackRecovery {
    static func detected(in tracks: [Track], activeTrackID: UUID?) -> [Track] {
        tracks
            .filter { $0.endedAt == nil && $0.id != activeTrackID }
            .sorted {
                ($0.startedAt, $0.id.uuidString.lowercased()) <
                    ($1.startedAt, $1.id.uuidString.lowercased())
            }
    }
}
