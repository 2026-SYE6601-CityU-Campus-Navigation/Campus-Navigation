import Foundation
import Observation
import SwiftData

// One form owns one recording session and one user selection. Camera events
// only replace the frozen evidence, never reseed location from the last node.
@MainActor
@Observable
final class NodeCaptureForm {
    let trackID: UUID?
    var selectedType: TrackTagType = .toilet
    var note = ""
    var selectedAreaID: UUID?
    var floor: String
    var selectedRoomID: UUID?
    var doorRole = "前门"
    private(set) var capture: CapturedTrackPhoto?

    init(trackID: UUID?, initialLocation: TagLocationContext) {
        self.trackID = trackID
        selectedAreaID = initialLocation.areaID
        floor = initialLocation.floor
    }

    func receive(_ result: CapturedTrackPhoto?) throws {
        guard let result else { return } // Cancelled retake preserves prior evidence.
        guard result.trackID == trackID else { throw NodeCaptureError.changedSession }
        capture = result
    }

    func request(availableAreaIDs: Set<UUID>, isNode: Bool, rooms: [Room] = []) throws -> NodeCaptureRequest {
        guard let capture, capture.trackID == trackID else { throw NodeCaptureError.changedSession }
        if isNode, let selectedAreaID, !availableAreaIDs.contains(selectedAreaID) {
            throw NodeCaptureError.areaUnavailable
        }
        let roomSelection = isNode ? selectedRoomID.map {
            NodeRoomSelection(roomID: $0, doorRole: selectedType == .classroom ? nil : doorRole)
        } : nil
        _ = try NodeRoomBinding.resolve(roomSelection, type: selectedType, areaID: selectedAreaID, rooms: rooms)
        return NodeCaptureRequest(capture: capture, type: selectedType, note: note,
            location: TagLocationContext(areaID: selectedAreaID,
                areaStateRawValue: selectedAreaID == nil ? "unassigned" : "assigned",
                floor: CampusCatalog.floor(floor)), roomSelection: roomSelection)
    }
}

// Immutable values captured by the Save action; no lazy lookup/fallback to A.
struct NodeCaptureRequest {
    let capture: CapturedTrackPhoto
    let type: TrackTagType
    let note: String
    let location: TagLocationContext
    let roomSelection: NodeRoomSelection?
}
