import Foundation

nonisolated struct Track3DVector: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct Track3DSample: Equatable, Sendable {
    let timeMs: Int64
    let position: Track3DVector
    let weak: Bool
    let startsNewPart: Bool
}

nonisolated struct Track3DPin: Identifiable, Equatable, Sendable {
    let id: UUID
    let position: Track3DVector
    let label: String
    let estimated: Bool
}

nonisolated struct Track3DPlan: Equatable, Sendable {
    enum HeightSource: String, Sendable {
        case altitude, pressure, flat
        var title: String {
            switch self {
            case .altitude: "GPS 海拔"
            case .pressure: "气压相对高度"
            case .flat: "无可用高度"
            }
        }
    }

    let samples: [Track3DSample]
    let pins: [Track3DPin]
    let heightSource: HeightSource
    let zScale: Double
    let omittedPointCount: Int
    let weakPointCount: Int
}

nonisolated enum Track3DPlanner {
    static let maximumAccuracy = 50.0
    static let weakAccuracy = 8.0
    static let gapMilliseconds: Int64 = 30_000
    private static let metersPerLatitudeDegree = 110_540.0
    private static let metersPerLongitudeDegree = 111_320.0

    struct Point: Equatable, Sendable {
        let timeMs: Int64
        let latitude: Double?
        let longitude: Double?
        let altitude: Double?
        let accuracy: Double?
        let pressureHpa: Double?
    }

    struct Pin: Equatable, Sendable {
        let id: UUID
        let timeMs: Int64
        let latitude: Double?
        let longitude: Double?
        let accuracy: Double?
        let label: String
    }

    static func build(points: [Point], pins: [Pin]) -> Track3DPlan {
        let ordered = points.sorted { $0.timeMs < $1.timeMs }
        let usable = ordered.filter(usableLocation)
        guard let origin = usable.first, let originLatitude = origin.latitude, let originLongitude = origin.longitude else {
            return .init(samples: [], pins: [], heightSource: .flat, zScale: 1,
                         omittedPointCount: points.count, weakPointCount: 0)
        }

        let heightSource = chooseHeightSource(usable)
        let altitudeOrigin = usable.compactMap(\.altitude).first
        let pressureOrigin = usable.compactMap(\.pressureHpa).first
        let longitudeScale = metersPerLongitudeDegree * cos(originLatitude * .pi / 180)
        var samples: [Track3DSample] = []
        for point in usable {
            guard let latitude = point.latitude, let longitude = point.longitude else { continue }
            let z: Double = switch heightSource {
            case .altitude: (point.altitude ?? altitudeOrigin ?? 0) - (altitudeOrigin ?? 0)
            case .pressure: ((pressureOrigin ?? point.pressureHpa ?? 0) - (point.pressureHpa ?? pressureOrigin ?? 0)) * 8.3
            case .flat: 0
            }
            let begins = samples.last.map { point.timeMs - $0.timeMs > gapMilliseconds } ?? true
            samples.append(.init(timeMs: point.timeMs,
                                 position: .init(x: (longitude - originLongitude) * longitudeScale,
                                                 y: (latitude - originLatitude) * metersPerLatitudeDegree,
                                                 z: z),
                                 weak: (point.accuracy ?? 0) > weakAccuracy,
                                 startsNewPart: begins))
        }
        let zScale = verticalScale(samples)
        let scaledSamples = samples.map {
            Track3DSample(timeMs: $0.timeMs,
                          position: .init(x: $0.position.x, y: $0.position.y, z: $0.position.z * zScale),
                          weak: $0.weak, startsNewPart: $0.startsNewPart)
        }
        let projectedPins = pins.enumerated().compactMap { index, pin -> Track3DPin? in
            let direct: Track3DVector?
            if let latitude = pin.latitude, let longitude = pin.longitude,
               latitude.isFinite, longitude.isFinite,
               pin.accuracy.map({ $0 >= 0 && $0 <= maximumAccuracy }) ?? true {
                let nearest = nearestSample(to: pin.timeMs, in: scaledSamples)
                direct = .init(x: (longitude - originLongitude) * longitudeScale,
                               y: (latitude - originLatitude) * metersPerLatitudeDegree,
                               z: nearest?.position.z ?? 0)
            } else {
                direct = nil
            }
            guard let position = direct ?? nearestSample(to: pin.timeMs, in: scaledSamples)?.position else { return nil }
            let prefix = "\(index + 1)"
            return .init(id: pin.id, position: position,
                         label: pin.label.isEmpty ? prefix : "\(prefix) · \(pin.label)", estimated: direct == nil)
        }
        return .init(samples: scaledSamples, pins: projectedPins, heightSource: heightSource,
                     zScale: zScale, omittedPointCount: points.count - usable.count,
                     weakPointCount: usable.filter { ($0.accuracy ?? 0) > weakAccuracy }.count)
    }

    static func usableLocation(_ point: Point) -> Bool {
        guard let latitude = point.latitude, let longitude = point.longitude,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        return point.accuracy.map { $0.isFinite && $0 >= 0 && $0 <= maximumAccuracy } ?? true
    }

    static func chooseHeightSource(_ points: [Point]) -> Track3DPlan.HeightSource {
        let altitudes = points.compactMap(\.altitude).filter(\.isFinite)
        if altitudes.count >= 2 { return .altitude }
        let pressure = points.compactMap(\.pressureHpa).filter { $0.isFinite && $0 > 0 }
        return pressure.count >= 2 ? .pressure : .flat
    }

    static func nearestSample(to timeMs: Int64, in samples: [Track3DSample]) -> Track3DSample? {
        samples.min { abs($0.timeMs - timeMs) < abs($1.timeMs - timeMs) }
    }

    private static func verticalScale(_ samples: [Track3DSample]) -> Double {
        guard samples.count > 1 else { return 1 }
        let xRange = (samples.map(\.position.x).max() ?? 0) - (samples.map(\.position.x).min() ?? 0)
        let yRange = (samples.map(\.position.y).max() ?? 0) - (samples.map(\.position.y).min() ?? 0)
        let zRange = (samples.map(\.position.z).max() ?? 0) - (samples.map(\.position.z).min() ?? 0)
        let horizontal = max(xRange, yRange, 1)
        guard zRange > 0 else { return 1 }
        return min(1, horizontal * 0.3 / zRange)
    }
}
