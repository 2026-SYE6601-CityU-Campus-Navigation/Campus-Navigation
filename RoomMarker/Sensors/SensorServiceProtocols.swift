import Foundation

@MainActor
protocol LocationSensorServicing: AnyObject {
    var permissionState: LocationPermissionState { get }
    var locationState: SensorValueState<LocationReading> { get }
    var headingState: SensorValueState<Double> { get }
    var onChange: (@MainActor () -> Void)? { get set }

    func requestWhenInUseAuthorization()
    func start()
    func stop()
}

@MainActor
protocol MagnetometerSensorServicing: AnyObject {
    var state: SensorValueState<MagneticFieldReading> { get }
    var onChange: (@MainActor () -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
protocol PressureSensorServicing: AnyObject {
    var state: SensorValueState<Double> { get }
    var onChange: (@MainActor () -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
protocol SensorHubProtocol: AnyObject {
    var state: LiveSensorState { get }
    var activeConsumerCount: Int { get }

    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool)
    func requestLocationAuthorization()
    func stop(consumer: SensorConsumer)
}
