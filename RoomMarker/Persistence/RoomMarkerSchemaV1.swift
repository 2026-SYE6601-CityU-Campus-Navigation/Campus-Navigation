import Foundation
import SwiftData

// Frozen persisted shape of the released V1 store. Do not reuse the evolving
// application models here: migration must still recognize an untouched old store.
enum RoomMarkerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Area.self, Room.self, Marker.self, Track.self, TrackPoint.self, TrackTag.self, TrackPhoto.self]
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
        var area: Area?

        @Relationship(deleteRule: .cascade, inverse: \TrackPoint.track)
        var points: [TrackPoint]

        @Relationship(deleteRule: .cascade, inverse: \TrackTag.track)
        var tags: [TrackTag]

        @Relationship(deleteRule: .cascade, inverse: \TrackPhoto.track)
        var photos: [TrackPhoto]

        var pointCount: Int { points.count }

        init(
            id: UUID = UUID(),
            name: String,
            area: Area? = nil,
            startedAt: Int64,
            endedAt: Int64? = nil
        ) {
            self.id = id
            self.name = name
            self.area = area
            self.startedAt = startedAt
            self.endedAt = endedAt
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

        var wifiAvailability: WiFiFingerprintAvailability {
            get { WiFiFingerprintAvailability(rawValue: wifiAvailabilityRawValue) ?? .unsupported }
            set { wifiAvailabilityRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            track: Track,
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
            wifiTop: String? = nil
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
            createdAt: Int64
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
            createdAt: Int64
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
        }
    }
}
