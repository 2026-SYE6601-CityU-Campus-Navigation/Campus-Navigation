import CoreMotion
import Foundation

@MainActor
final class CoreMotionMagnetometerService: MagnetometerSensorServicing {
    private let manager: CMMotionManager
    private var staleTask: Task<Void, Never>?
    private var isRunning = false

    private(set) var state: SensorValueState<MagneticFieldReading> = .waiting
    var onChange: (@MainActor () -> Void)?

    init(manager: CMMotionManager = CMMotionManager()) {
        self.manager = manager
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        guard manager.isMagnetometerAvailable else {
            state = .unsupported
            publish()
            return
        }

        state = .waiting
        manager.magnetometerUpdateInterval = 0.25
        manager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            let hasError = error != nil
            let reading = data.map {
                MagneticFieldReading(
                    x: $0.magneticField.x,
                    y: $0.magneticField.y,
                    z: $0.magneticField.z
                )
            }
            Task { @MainActor [weak self, reading] in
                guard let self, self.isRunning else { return }
                if let reading,
                   reading.x.isFinite,
                   reading.y.isFinite,
                   reading.z.isFinite
                {
                    let sample = TimestampedSensorValue(value: reading, capturedAt: Date())
                    self.state = .available(sample)
                    self.markStale(after: sample)
                } else if hasError, self.state.availableValue == nil {
                    self.state = .unavailable
                }
                self.publish()
            }
        }
        publish()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopMagnetometerUpdates()
        staleTask?.cancel()
        staleTask = nil
    }

    private func publish() {
        onChange?()
    }

    private func markStale(after sample: TimestampedSensorValue<MagneticFieldReading>) {
        staleTask?.cancel()
        staleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard let self, self.isRunning,
                  case let .available(current) = self.state,
                  current.capturedAt == sample.capturedAt
            else { return }
            self.state = .stale(current)
            self.publish()
        }
    }
}
