import Foundation
import SwiftData

// Manual evidence, separate from the periodic TrackPoint stream and photo nodes.
@Model
final class TrackCorner {
    @Attribute(.unique) var id: UUID
    var timeMs: Int64
    var note: String
    var segmentID: UUID?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var accuracy: Double?
    var pressureHpa: Double?
    var magneticX: Double?
    var magneticY: Double?
    var magneticZ: Double?
    var headingDeg: Double?
    var track: Track?

    init(id: UUID = UUID(), track: Track?, sample: TrackPointDraft, note: String = "") {
        self.id = id
        self.track = track
        timeMs = sample.timeMs
        segmentID = sample.segmentID
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        latitude = sample.latitude
        longitude = sample.longitude
        altitude = sample.altitude
        accuracy = sample.accuracy
        pressureHpa = sample.pressureHpa
        magneticX = sample.magneticX
        magneticY = sample.magneticY
        magneticZ = sample.magneticZ
        headingDeg = sample.headingDeg
    }
}
