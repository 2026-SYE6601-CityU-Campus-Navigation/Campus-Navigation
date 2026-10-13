import CoreMotion
import Foundation

@MainActor
final class CoreMotionRawIMUService: RawIMUServicing {
    private let manager: CMMotionManager
    private var generation = UUID()
    private var running = false
    private var failedChannels: Set<RawIMUKind> = []

    // Production shares this manager with the existing magnetometer adapter.
    init(manager: CMMotionManager) { self.manager = manager }

    func start(interval: TimeInterval, handler: @escaping @MainActor @Sendable (RawIMUEvent) -> Void) {
        guard !running else { return }
        running = true
        failedChannels.removeAll()
        generation = UUID()
        let token = generation
        if manager.isAccelerometerAvailable {
            handler(.state(.accelerometer, .waiting))
            manager.accelerometerUpdateInterval = interval
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                let reading = data.map {
                    RawIMUReading(kind: .accelerometer, sensorTimeSeconds: $0.timestamp,
                                  x: $0.acceleration.x, y: $0.acceleration.y, z: $0.acceleration.z)
                }
                let failure = Self.failureState(error)
                // OperationQueue.main guarantees main-actor delivery. No unbounded
                // Task-per-reading bridge or resampling timer is introduced.
                MainActor.assumeIsolated {
                    self?.deliver(reading, failure: failure, kind: .accelerometer, token: token, handler: handler)
                }
            }
        } else { handler(.state(.accelerometer, .unsupported)) }

        if manager.isGyroAvailable {
            handler(.state(.gyroscope, .waiting))
            manager.gyroUpdateInterval = interval
            manager.startGyroUpdates(to: .main) { [weak self] data, error in
                let reading = data.map {
                    RawIMUReading(kind: .gyroscope, sensorTimeSeconds: $0.timestamp,
                                  x: $0.rotationRate.x, y: $0.rotationRate.y, z: $0.rotationRate.z)
                }
                let failure = Self.failureState(error)
                MainActor.assumeIsolated {
                    self?.deliver(reading, failure: failure, kind: .gyroscope, token: token, handler: handler)
                }
            }
        } else { handler(.state(.gyroscope, .unsupported)) }
    }

    func stop() {
        generation = UUID()
        guard running else { return }
        running = false
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        // Do not stop magnetometer, pressure or location consumers.
    }

    nonisolated static func failureState(_ error: Error?) -> RawIMUChannelState? {
        guard let error = error as NSError? else { return nil }
        let deniedCodes = [Int(CMErrorNotAuthorized.rawValue), Int(CMErrorMotionActivityNotAuthorized.rawValue)]
        return error.domain == CMErrorDomain && deniedCodes.contains(error.code) ? .denied : .unavailable
    }

    private func deliver(
        _ reading: RawIMUReading?, failure: RawIMUChannelState?, kind: RawIMUKind,
        token: UUID, handler: @MainActor @Sendable (RawIMUEvent) -> Void
    ) {
        guard running, generation == token, !failedChannels.contains(kind) else { return }
        if let failure {
            failedChannels.insert(kind)
            if kind == .accelerometer { manager.stopAccelerometerUpdates() } else { manager.stopGyroUpdates() }
            handler(.state(kind, failure))
        } else if let reading { handler(.reading(reading)) }
    }
}
