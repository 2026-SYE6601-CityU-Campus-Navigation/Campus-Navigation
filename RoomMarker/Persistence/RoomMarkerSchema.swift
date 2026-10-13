import Foundation
import SwiftData

enum RoomMarkerSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Area.self,
            Room.self,
            Marker.self,
            Track.self,
            TrackPoint.self,
            TrackTag.self,
            TrackPhoto.self,
            TrackSegment.self,
            TrackCorner.self,
            TrackIMUBatch.self,
        ]
    }
}

enum RoomMarkerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoomMarkerSchemaV1.self, RoomMarkerSchemaV2.self, RoomMarkerSchemaV3.self, RoomMarkerSchemaV4.self, RoomMarkerSchemaV5.self, RoomMarkerSchemaV6.self, RoomMarkerSchemaV7.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: RoomMarkerSchemaV1.self,
                toVersion: RoomMarkerSchemaV2.self
            ),
            .lightweight(fromVersion: RoomMarkerSchemaV2.self, toVersion: RoomMarkerSchemaV3.self),
            .lightweight(fromVersion: RoomMarkerSchemaV3.self, toVersion: RoomMarkerSchemaV4.self),
            .lightweight(fromVersion: RoomMarkerSchemaV4.self, toVersion: RoomMarkerSchemaV5.self),
            .lightweight(fromVersion: RoomMarkerSchemaV5.self, toVersion: RoomMarkerSchemaV6.self),
            .lightweight(fromVersion: RoomMarkerSchemaV6.self, toVersion: RoomMarkerSchemaV7.self),
        ]
    }
}

enum RoomMarkerModelContainer {
    static func make(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        guard !inMemory || storeURL == nil else {
            throw RoomMarkerStoreConfigurationError.diskURLForInMemoryStore
        }
        let schema = Schema(versionedSchema: RoomMarkerSchemaV7.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration("RoomMarker", schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(
                "RoomMarker",
                schema: schema,
                isStoredInMemoryOnly: inMemory
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: RoomMarkerMigrationPlan.self,
            configurations: configuration
        )
    }
}

enum RoomMarkerStoreConfigurationError: Error {
    case diskURLForInMemoryStore
}
