import Foundation

enum MarkerType: String, Codable, CaseIterable, Sendable {
    case frontDoor = "前门"
    case backDoor = "后门"
    case window = "窗户"
    case corner = "墙角"
    case socket = "插座"
    case custom = "自定义"
}
