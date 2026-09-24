import SwiftData

enum RoomMarkerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
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
        ]
    }
}

enum RoomMarkerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoomMarkerSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum RoomMarkerModelContainer {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(RoomMarkerSchemaV1.models)
        let configuration = ModelConfiguration(
            "RoomMarker",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: RoomMarkerMigrationPlan.self,
            configurations: configuration
        )
    }
}
