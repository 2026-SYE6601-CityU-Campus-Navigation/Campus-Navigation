import Foundation

nonisolated struct PlaceLandmark: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let areaName: String
    let floor: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let pressureHpa: Double?
}

nonisolated struct PlaceCandidate: Identifiable, Equatable, Sendable {
    var id: UUID { landmark.id }
    let landmark: PlaceLandmark
    let distanceMeters: Double
    let pressureDifferenceHpa: Double?
}

nonisolated struct PlaceRecognitionResult: Equatable, Sendable {
    let candidates: [PlaceCandidate]
    let accepted: PlaceCandidate?
    let explanation: String
}

nonisolated enum PlaceRecognitionEngine {
    static let maximumLocationAccuracy = 50.0

    static func recognize(latitude: Double, longitude: Double, accuracy: Double?, pressureHpa: Double?,
                          landmarks: [PlaceLandmark]) -> PlaceRecognitionResult {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return .init(candidates: [], accepted: nil, explanation: "当前定位无效，未生成地点结果。")
        }
        guard let accuracy, accuracy.isFinite, accuracy >= 0, accuracy <= maximumLocationAccuracy else {
            return .init(candidates: [], accepted: nil,
                         explanation: "当前水平精度不足 50 m，未把网络定位猜成室内地点。")
        }
        let ranked = landmarks.map { landmark in
            PlaceCandidate(landmark: landmark,
                           distanceMeters: distance(latitude, longitude, landmark.latitude, landmark.longitude),
                           pressureDifferenceHpa: pressureHpa.flatMap { current in
                               landmark.pressureHpa.map { abs(current - $0) }
                           })
        }.sorted {
            if $0.distanceMeters != $1.distanceMeters { return $0.distanceMeters < $1.distanceMeters }
            return $0.landmark.id.uuidString < $1.landmark.id.uuidString
        }
        let shown = Array(ranked.prefix(5))
        guard let best = shown.first else {
            return .init(candidates: [], accepted: nil, explanation: "尚无带可用坐标的历史节点。")
        }
        let allowed = max(20, accuracy + (best.landmark.accuracy ?? 0))
        let margin = shown.dropFirst().first.map { $0.distanceMeters - best.distanceMeters } ?? .infinity
        let pressurePlausible = best.pressureDifferenceHpa.map { $0 <= 3.5 } ?? true
        let accepted = best.distanceMeters <= allowed && margin >= 5 && pressurePlausible ? best : nil
        let explanation: String
        if accepted != nil {
            explanation = "结果由当前位置与历史节点距离计算；气压只作一致性检查，不是连续室内定位。"
        } else if !pressurePlausible {
            explanation = "最近节点的气压差较大，可能不在同一楼层，因此未确认地点。"
        } else if best.distanceMeters > allowed {
            explanation = "最近节点仍超出当前定位精度范围，因此未确认地点。"
        } else {
            explanation = "前两名距离过近，无法可靠区分，因此未确认地点。"
        }
        return .init(candidates: shown, accepted: accepted, explanation: explanation)
    }

    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
