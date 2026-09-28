import CoreMotion
import Foundation

@MainActor
final class CoreMotionPressureService: PressureSensorServicing {
    private let altimeter: CMAltimeter
    private var staleTask: Task<Void, Never>?
    private var isRunning = false

    private(set) var state: SensorValueState<Double> = .waiting
    var onChange: (@MainActor () -> Void)?

    init(altimeter: CMAltimeter = CMAltimeter()) {
        self.altimeter = altimeter
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            state = .unsupported
            publish()
            return
        }

        state = .waiting
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            let pressureKpa = data?.pressure.doubleValue
            let hasError = error != nil
            Task { @MainActor [weak self, pressureKpa] in
                guard let self, self.isRunning else { return }
                if let pressureKpa,
                   let pressureHpa = Self.hectopascals(fromKilopascals: pressureKpa)
                {
                    let sample = TimestampedSensorValue(value: pressureHpa, capturedAt: Date())
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
        altimeter.stopRelativeAltitudeUpdates()
        staleTask?.cancel()
        staleTask = nil
    }

    static func hectopascals(fromKilopascals kilopascals: Double) -> Double? {
        guard kilopascals.isFinite, kilopascals >= 0 else { return nil }
        return kilopascals * 10
    }

    private func publish() {
        onChange?()
    }

    private func markStale(after sample: TimestampedSensorValue<Double>) {
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
