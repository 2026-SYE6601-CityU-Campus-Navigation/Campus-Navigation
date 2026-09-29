import Foundation

enum TrackTagType: String, Codable, CaseIterable, Sendable {
    case toilet = "厕所"
    case stairs = "楼梯"
    case door = "门"
    case gate = "门禁"
    case elevator = "电梯"
    case classroom = "教室"
}
