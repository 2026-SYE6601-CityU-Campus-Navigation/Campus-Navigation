import Foundation
import Testing
@testable import RoomMarker

@Suite("Full parity recognition and 3D planning")
struct FullParityRecognitionAnd3DTests {
    @Test("3D planning rejects poor points, marks weak evidence and breaks real timestamp gaps")
    func threeDimensionalPlan() throws {
        let points = [
            Track3DPlanner.Point(timeMs: 1_000, latitude: 22.3000, longitude: 114.1000,
                                 altitude: 10, accuracy: 3, pressureHpa: 1_008),
            Track3DPlanner.Point(timeMs: 2_000, latitude: 22.3001, longitude: 114.1001,
                                 altitude: 12, accuracy: 12, pressureHpa: 1_007.8),
            Track3DPlanner.Point(timeMs: 40_000, latitude: 22.3002, longitude: 114.1002,
                                 altitude: 14, accuracy: 3, pressureHpa: 1_007.5),
            Track3DPlanner.Point(timeMs: 41_000, latitude: 22.4, longitude: 114.2,
                                 altitude: 20, accuracy: 100, pressureHpa: 1_007),
        ]
        let pins = [Track3DPlanner.Pin(id: UUID(), timeMs: 2_100, latitude: nil, longitude: nil,
                                       accuracy: nil, label: "Door")]
        let plan = Track3DPlanner.build(points: points, pins: pins)
        #expect(plan.samples.count == 3 && plan.omittedPointCount == 1 && plan.weakPointCount == 1)
        #expect(plan.heightSource == .altitude && plan.zScale > 0 && plan.zScale <= 1)
        #expect(plan.samples.map(\.startsNewPart) == [true, false, true])
        #expect(plan.pins.first?.estimated == true && plan.pins.first?.label == "1 · Door")
        #expect(plan.pins.first?.position == plan.samples[1].position)
    }

    @Test("Pressure is an honest relative-height fallback and no height remains flat")
    func heightFallbacks() {
        let pressure = [
            Track3DPlanner.Point(timeMs: 1, latitude: 22.3, longitude: 114.1,
                                 altitude: nil, accuracy: 3, pressureHpa: 1_008),
            Track3DPlanner.Point(timeMs: 2, latitude: 22.3001, longitude: 114.1001,
                                 altitude: nil, accuracy: 3, pressureHpa: 1_007),
        ]
        let pressurePlan = Track3DPlanner.build(points: pressure, pins: [])
        #expect(pressurePlan.heightSource == .pressure)
        #expect(pressurePlan.samples.last?.position.z != 0)
        let flat = pressure.map {
            Track3DPlanner.Point(timeMs: $0.timeMs, latitude: $0.latitude, longitude: $0.longitude,
                                 altitude: nil, accuracy: $0.accuracy, pressureHpa: nil)
        }
        #expect(Track3DPlanner.build(points: flat, pins: []).heightSource == .flat)
    }

    @Test("Place recognition accepts only a clear, accurate and pressure-plausible nearest node")
    func conservativeRecognition() throws {
        let near = PlaceLandmark(id: UUID(), label: "A", areaName: "Building A", floor: "1/F",
                                 latitude: 22.3000, longitude: 114.1000,
                                 accuracy: 3, pressureHpa: 1_008)
        let far = PlaceLandmark(id: UUID(), label: "B", areaName: "Building B", floor: "2/F",
                                latitude: 22.3010, longitude: 114.1010,
                                accuracy: 3, pressureHpa: 1_004)
        let accepted = PlaceRecognitionEngine.recognize(latitude: 22.30001, longitude: 114.10001,
                                                         accuracy: 5, pressureHpa: 1_008.5,
                                                         landmarks: [far, near])
        #expect(accepted.accepted?.landmark.id == near.id)
        #expect(accepted.candidates.map(\.landmark.id).first == near.id)

        let weak = PlaceRecognitionEngine.recognize(latitude: 22.3, longitude: 114.1,
                                                     accuracy: 80, pressureHpa: nil,
                                                     landmarks: [near])
        #expect(weak.accepted == nil && weak.candidates.isEmpty)
        let wrongFloor = PlaceRecognitionEngine.recognize(latitude: 22.3, longitude: 114.1,
                                                           accuracy: 5, pressureHpa: 1_000,
                                                           landmarks: [near])
        #expect(wrongFloor.accepted == nil && wrongFloor.candidates.count == 1)
    }

    @Test("Ambiguous nearby nodes are listed but never presented as a confirmed room")
    func ambiguity() {
        let landmarks = [
            PlaceLandmark(id: UUID(), label: "A", areaName: "X", floor: "", latitude: 22.3,
                          longitude: 114.1, accuracy: 3, pressureHpa: nil),
            PlaceLandmark(id: UUID(), label: "B", areaName: "X", floor: "", latitude: 22.30001,
                          longitude: 114.10001, accuracy: 3, pressureHpa: nil),
        ]
        let result = PlaceRecognitionEngine.recognize(latitude: 22.3, longitude: 114.1,
                                                       accuracy: 5, pressureHpa: nil,
                                                       landmarks: landmarks)
        #expect(result.candidates.count == 2 && result.accepted == nil)
    }
}
