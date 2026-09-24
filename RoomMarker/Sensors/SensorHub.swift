import Observation

@MainActor
@Observable
final class SensorHub: SensorHubProtocol {
    @ObservationIgnored private let locationService: any LocationSensorServicing
    @ObservationIgnored private let magnetometerService: any MagnetometerSensorServicing
    @ObservationIgnored private let pressureService: any PressureSensorServicing
    @ObservationIgnored private var activeConsumers: Set<SensorConsumer> = []

    private(set) var state: LiveSensorState

    var activeConsumerCount: Int {
        activeConsumers.count
    }

    init(
        locationService: any LocationSensorServicing = CoreLocationSensorService(),
        magnetometerService: any MagnetometerSensorServicing = CoreMotionMagnetometerService(),
        pressureService: any PressureSensorServicing = CoreMotionPressureService()
    ) {
        self.locationService = locationService
        self.magnetometerService = magnetometerService
        self.pressureService = pressureService
        state = LiveSensorState(
            permission: locationService.permissionState,
            location: locationService.locationState,
            pressureHpa: pressureService.state,
            magneticField: magnetometerService.state,
            headingDeg: locationService.headingState
        )

        locationService.onChange = { [weak self] in self?.synchronize() }
        magnetometerService.onChange = { [weak self] in self?.synchronize() }
        pressureService.onChange = { [weak self] in self?.synchronize() }
    }

    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) {
        let wasIdle = activeConsumers.isEmpty
        activeConsumers.insert(consumer)

        if wasIdle {
            locationService.start()
            magnetometerService.start()
            pressureService.start()
        }
        if requestLocationAuthorization {
            locationService.requestWhenInUseAuthorization()
        }
        synchronize()
    }

    func requestLocationAuthorization() {
        locationService.requestWhenInUseAuthorization()
        synchronize()
    }

    func stop(consumer: SensorConsumer) {
        activeConsumers.remove(consumer)
        guard activeConsumers.isEmpty else { return }
        locationService.stop()
        magnetometerService.stop()
        pressureService.stop()
    }

    private func synchronize() {
        state = LiveSensorState(
            permission: locationService.permissionState,
            location: locationService.locationState,
            pressureHpa: pressureService.state,
            magneticField: magnetometerService.state,
            headingDeg: locationService.headingState
        )
    }
}
