import Foundation

@MainActor
protocol RoomMarkerRepository: AnyObject {
    func save() throws
    func deleteAreaPreservingContents(_ area: Area) throws
    func deleteRoom(_ room: Room) throws
    func deleteTrack(_ track: Track) throws
}
