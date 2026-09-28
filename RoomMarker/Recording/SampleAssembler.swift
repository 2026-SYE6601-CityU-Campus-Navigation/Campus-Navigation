import Foundation

struct SampleAssembler: Sendable {
    func assemble(timeMs: Int64, state: LiveSensorState) -> TrackPointDraft {
        let location = state.location.availableValue
        let magnetic = state.magneticField.availableValue

        return TrackPointDraft(
            timeMs: timeMs,
            latitude: finite(location?.latitude),
            longitude: finite(location?.longitude),
            altitude: finite(location?.altitude),
            accuracy: nonnegativeFinite(location?.horizontalAccuracy),
            pressureHpa: nonnegativeFinite(state.pressureHpa.availableValue),
            magneticX: finite(magnetic?.x),
            magneticY: finite(magnetic?.y),
            magneticZ: finite(magnetic?.z),
            headingDeg: normalizedHeading(state.headingDeg.availableValue),
            wifiAvailability: .unsupported,
            wifiCount: nil,
            wifiTop: nil
        )
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private func normalizedHeading(_ value: Double?) -> Double? {
        guard let value = finite(value) else { return nil }
        let normalized = value.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}
