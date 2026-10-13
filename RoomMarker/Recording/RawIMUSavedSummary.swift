import Foundation

// Presentation-only session summary, not a new database or export format.
// Live rendering reads O(1) counters and at most four already accepted samples.
struct RawIMUSavedSummary: Equatable {
    private(set) var accelerationCount = 0
    private(set) var gyroscopeCount = 0
    private(set) var recentSamples: [RawIMUSample] = []
    var sampleCount: Int { accelerationCount + gyroscopeCount }

    mutating func append(_ samples: [RawIMUSample]) {
        guard !samples.isEmpty else { return }
        accelerationCount += samples.filter { $0.kind == .accelerometer }.count
        gyroscopeCount += samples.filter { $0.kind == .gyroscope }.count
        recentSamples = Array((recentSamples + samples).suffix(4))
    }

    // Called once when displaying a saved/interrupted Track, not on every
    // render of an active recording. Only the latest payload is decoded.
    static func read(_ track: Track) throws -> Self {
        var result = Self()
        var latest: TrackIMUBatch?
        for batch in track.imuBatches {
            result.accelerationCount += batch.accelerationCount
            result.gyroscopeCount += batch.gyroscopeCount
            if latest.map({ batch.lastTimeMs > $0.lastTimeMs }) ?? true { latest = batch }
        }
        if let latest { result.recentSamples = Array(try latest.decodedSamples().suffix(4)) }
        return result
    }
}
