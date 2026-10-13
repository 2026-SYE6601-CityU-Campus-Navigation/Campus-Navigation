import Foundation

nonisolated enum TrackTagType: String, Codable, CaseIterable, Sendable {
    case toilet = "厕所"
    case stairs = "楼梯"
    case door = "门"
    case gate = "门禁"
    case elevator = "电梯"
    case classroom = "教室"
    case mainGate = "大门"
    case escalator = "扶梯"
    case canteen = "食堂"
    case shop = "商店"
    case otherIndoor = "其他室内"
}
