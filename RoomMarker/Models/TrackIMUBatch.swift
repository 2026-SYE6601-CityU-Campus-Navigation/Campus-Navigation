import Foundation
import SwiftData

// Bounded binary payloads in the same database, not a row per 50 Hz event.
@Model
final class TrackIMUBatch {
    @Attribute(.unique) var id: UUID
    var track: Track?
    var payload: Data
    var sampleCount: Int
    var accelerationCount: Int
    var gyroscopeCount: Int
    var firstTimeMs: Int64
    var lastTimeMs: Int64
    var lastAccelerationTime: Double?
    var lastGyroscopeTime: Double?

    init(id: UUID, samples: [RawIMUSample], payload: Data) {
        self.id = id
        self.payload = payload
        sampleCount = samples.count
        accelerationCount = samples.filter { $0.kind == .accelerometer }.count
        gyroscopeCount = samples.filter { $0.kind == .gyroscope }.count
        firstTimeMs = samples.map(\.timeMs).min() ?? 0
        lastTimeMs = samples.map(\.timeMs).max() ?? 0
        lastAccelerationTime = samples.filter { $0.kind == .accelerometer }.map(\.sensorTimeSeconds).max()
        lastGyroscopeTime = samples.filter { $0.kind == .gyroscope }.map(\.sensorTimeSeconds).max()
    }

    func decodedSamples() throws -> [RawIMUSample] {
        let samples = try JSONDecoder().decode([RawIMUSample].self, from: payload)
        guard !samples.isEmpty, samples.count <= RawIMUPolicy.batchSize,
              samples.count == sampleCount,
              samples.filter({ $0.kind == .accelerometer }).count == accelerationCount,
              samples.filter({ $0.kind == .gyroscope }).count == gyroscopeCount,
              samples.map(\.timeMs).min() == firstTimeMs,
              samples.map(\.timeMs).max() == lastTimeMs,
              samples.filter({ $0.kind == .accelerometer }).map(\.sensorTimeSeconds).max() == lastAccelerationTime,
              samples.filter({ $0.kind == .gyroscope }).map(\.sensorTimeSeconds).max() == lastGyroscopeTime,
              samples.allSatisfy(\.isFinite) else { throw RawIMUError.invalidBatch }
        return samples
    }
}
