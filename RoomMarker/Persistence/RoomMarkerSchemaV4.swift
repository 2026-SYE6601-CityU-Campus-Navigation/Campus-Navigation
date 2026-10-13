import Foundation
import SwiftData

// Frozen Stage 3 store shape. Never evolve these nine historical models.
enum RoomMarkerSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Area.self, Room.self, Marker.self, Track.self, TrackPoint.self, TrackTag.self, TrackPhoto.self, TrackSegment.self, TrackCorner.self]
    }

    @Model
    final class Area {
        @Attribute(.unique) var id: UUID
        var name: String
        var note: String
        var createdAt: Int64

        @Relationship(deleteRule: .nullify, inverse: \Room.area)
        var rooms: [Room]

        @Relationship(deleteRule: .nullify, inverse: \Track.area)
        var tracks: [Track]

        init(
            id: UUID = UUID(),
            name: String,
            note: String = "",
            createdAt: Int64
        ) {
            self.id = id
            self.name = name
            self.note = note
            self.createdAt = createdAt
            rooms = []
            tracks = []
        }
    }

    @Model
    final class Room {
        @Attribute(.unique) var id: UUID
        var name: String
        var note: String
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var pressureHpa: Double?
        var createdAt: Int64
        var area: Area?

        @Relationship(deleteRule: .cascade, inverse: \Marker.room)
        var markers: [Marker]

        init(
            id: UUID = UUID(),
            name: String,
            note: String = "",
            area: Area? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            altitude: Double? = nil,
            pressureHpa: Double? = nil,
            createdAt: Int64
        ) {
            self.id = id
            self.name = name
            self.note = note
            self.area = area
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.pressureHpa = pressureHpa
            self.createdAt = createdAt
            markers = []
        }
    }

    @Model
    final class Marker {
        @Attribute(.unique) var id: UUID
        var name: String
        var markerTypeRawValue: String
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var accuracy: Double?
        var pressureHpa: Double?
        var magneticX: Double?
        var magneticY: Double?
        var magneticZ: Double?
        var createdAt: Int64
        var room: Room?

        var markerType: MarkerType? {
            get { MarkerType(rawValue: markerTypeRawValue) }
            set { markerTypeRawValue = newValue?.rawValue ?? markerTypeRawValue }
        }

        init(
            id: UUID = UUID(),
            room: Room,
            name: String,
            markerType: MarkerType,
            latitude: Double? = nil,
            longitude: Double? = nil,
            altitude: Double? = nil,
            accuracy: Double? = nil,
            pressureHpa: Double? = nil,
            magneticX: Double? = nil,
            magneticY: Double? = nil,
            magneticZ: Double? = nil,
            createdAt: Int64
        ) {
            self.id = id
            self.room = room
            self.name = name
            markerTypeRawValue = markerType.rawValue
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.accuracy = accuracy
            self.pressureHpa = pressureHpa
            self.magneticX = magneticX
            self.magneticY = magneticY
            self.magneticZ = magneticZ
            self.createdAt = createdAt
        }
    }

    @Model
    final class Track {
        @Attribute(.unique) var id: UUID
        var name: String
        var startedAt: Int64
        var endedAt: Int64?
        // Retained only as the historical area hint for pre-global recordings.
        var area: Area?
        var legacyAreaName: String?
        var isGlobalRecording: Bool = false
        var isSegmentedRecording: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \TrackPoint.track)
        var points: [TrackPoint]

        @Relationship(deleteRule: .cascade, inverse: \TrackTag.track)
        var tags: [TrackTag]

        @Relationship(deleteRule: .cascade, inverse: \TrackPhoto.track)
        var photos: [TrackPhoto]

        @Relationship(deleteRule: .cascade, inverse: \TrackSegment.track)
        var segments: [TrackSegment] = []

        @Relationship(deleteRule: .cascade, inverse: \TrackCorner.track)
        var corners: [TrackCorner] = []

        var pointCount: Int { points.count }

        init(
            id: UUID = UUID(),
            name: String,
            area: Area? = nil,
            startedAt: Int64,
            endedAt: Int64? = nil,
            isGlobalRecording: Bool = false,
            legacyAreaName: String? = nil
        ) {
            self.id = id
            self.name = name
            self.area = area
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.isGlobalRecording = isGlobalRecording
            self.legacyAreaName = legacyAreaName
            points = []
            tags = []
            photos = []
        }
    }

    @Model
    final class TrackPoint {
        @Attribute(.unique) var id: UUID
        var timeMs: Int64
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var accuracy: Double?
        var pressureHpa: Double?
        var magneticX: Double?
        var magneticY: Double?
        var magneticZ: Double?
        var headingDeg: Double?
        var wifiAvailabilityRawValue: String
        var wifiCount: Int?
        var wifiTop: String?
        var track: Track?
        // Nil for pre-segmentation data: never infer historical environment.
        var segmentID: UUID?

        var wifiAvailability: WiFiFingerprintAvailability {
            get { WiFiFingerprintAvailability(rawValue: wifiAvailabilityRawValue) ?? .unsupported }
            set { wifiAvailabilityRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            track: Track?,
            timeMs: Int64,
            latitude: Double? = nil,
            longitude: Double? = nil,
            altitude: Double? = nil,
            accuracy: Double? = nil,
            pressureHpa: Double? = nil,
            magneticX: Double? = nil,
            magneticY: Double? = nil,
            magneticZ: Double? = nil,
            headingDeg: Double? = nil,
            wifiAvailability: WiFiFingerprintAvailability = .unsupported,
            wifiCount: Int? = nil,
            wifiTop: String? = nil,
            segmentID: UUID? = nil
        ) {
            self.id = id
            self.track = track
            self.timeMs = timeMs
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.accuracy = accuracy
            self.pressureHpa = pressureHpa
            self.magneticX = magneticX
            self.magneticY = magneticY
            self.magneticZ = magneticZ
            self.headingDeg = headingDeg
            wifiAvailabilityRawValue = wifiAvailability.rawValue
            self.wifiCount = wifiCount
            self.wifiTop = wifiTop
            self.segmentID = segmentID
        }
    }

    @Model
    final class TrackTag {
        @Attribute(.unique) var id: UUID
        var timeMs: Int64
        var tagTypeRawValue: String
        var note: String
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var headingDeg: Double?
        var createdAt: Int64
        var track: Track?
        // Scalar ownership avoids a delete cascade from an Area into a cross-building track.
        var areaID: UUID?
        var areaStateRawValue: String = "unknown"
        var floor: String = ""
        // Migration never infers a node from an old independent tag.
        var recordKindRawValue: String = "legacy"

        var isNode: Bool { recordKindRawValue == "node" }

        var tagType: TrackTagType? {
            get { TrackTagType(rawValue: tagTypeRawValue) }
            set { tagTypeRawValue = newValue?.rawValue ?? tagTypeRawValue }
        }

        init(
            id: UUID = UUID(),
            track: Track,
            timeMs: Int64,
            tagType: TrackTagType,
            note: String = "",
            latitude: Double? = nil,
            longitude: Double? = nil,
            altitude: Double? = nil,
            headingDeg: Double? = nil,
            createdAt: Int64,
            areaID: UUID? = nil,
            areaStateRawValue: String = "unknown",
            floor: String = "",
            recordKindRawValue: String = "legacy"
        ) {
            self.id = id
            self.track = track
            self.timeMs = timeMs
            tagTypeRawValue = tagType.rawValue
            self.note = note
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.headingDeg = headingDeg
            self.createdAt = createdAt
            self.areaID = areaID
            self.areaStateRawValue = areaStateRawValue
            self.floor = floor
            self.recordKindRawValue = recordKindRawValue
        }
    }

    @Model
    final class TrackPhoto {
        @Attribute(.unique) var id: UUID
        var timeMs: Int64
        var filePath: String
        var note: String
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
        var headingDeg: Double?
        var createdAt: Int64
        var track: Track?
        var kindRawValue: String = "legacyUnlinked"
        var tagID: UUID?

        var isNodePhoto: Bool { kindRawValue == "node" }

        init(
            id: UUID = UUID(),
            track: Track,
            timeMs: Int64,
            filePath: String,
            note: String = "",
            latitude: Double? = nil,
            longitude: Double? = nil,
            altitude: Double? = nil,
            headingDeg: Double? = nil,
            createdAt: Int64,
            kindRawValue: String = "legacyUnlinked",
            tagID: UUID? = nil
        ) {
            self.id = id
            self.track = track
            self.timeMs = timeMs
            self.filePath = filePath
            self.note = note
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.headingDeg = headingDeg
            self.createdAt = createdAt
            self.kindRawValue = kindRawValue
            self.tagID = tagID
        }
    }

    @Model
    final class TrackSegment {
        @Attribute(.unique) var id: UUID
        var ordinal: Int
        var startedAt: Int64
        var endedAt: Int64?
        var environmentRawValue: String
        var track: Track?

        var environment: TrackEnvironment? { TrackEnvironment(rawValue: environmentRawValue) }

        init(
            id: UUID = UUID(), track: Track?, ordinal: Int,
            startedAt: Int64, endedAt: Int64? = nil, environment: TrackEnvironment
        ) {
            self.id = id
            self.track = track
            self.ordinal = ordinal
            self.startedAt = startedAt
            self.endedAt = endedAt
            environmentRawValue = environment.rawValue
        }
    }

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
}
