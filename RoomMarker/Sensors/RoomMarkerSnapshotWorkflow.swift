import Foundation

@MainActor
final class RoomMarkerSnapshotWorkflow {
    private let snapshotService: any SensorSnapshotCapturing

    init(snapshotService: any SensorSnapshotCapturing) {
        self.snapshotService = snapshotService
    }

    @discardableResult
    func captureRoomReference(
        for room: Room,
        using store: Phase2DataStore
    ) async throws -> SensorSnapshot {
        let snapshot = try await snapshotService.capture()
        try store.replaceRoomReference(room, with: snapshot)
        return snapshot
    }

    @discardableResult
    func captureAndCreateMarker(
        in room: Room,
        name: String,
        markerType: MarkerType,
        createdAt: Int64 = Phase2DataStore.nowMilliseconds(),
        using store: Phase2DataStore
    ) async throws -> Marker {
        let snapshot = try await snapshotService.capture()
        return try store.createMarker(
            room: room,
            name: name,
            markerType: markerType,
            snapshot: snapshot,
            createdAt: createdAt
        )
    }
}
