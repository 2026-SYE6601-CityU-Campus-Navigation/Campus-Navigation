import CoreMotion
import SwiftData
import SwiftUI

@main
struct RoomMarkerApp: App {
    @State private var services: RoomMarkerAppServices?

    init() {
        do {
            _services = State(initialValue: try RoomMarkerAppServices())
        } catch {
            // Never replace/reset a store after a failed open or migration.
            _services = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let services {
                AreaListView(
                    sensorHub: services.sensorHub,
                    recordingCoordinator: services.recordingCoordinator,
                    cameraService: services.cameraService,
                    photoStorage: services.photoStorage,
                    snapshotService: services.snapshotService
                )
                .modelContainer(services.modelContainer)
            } else {
                ContentUnavailableView(
                    "无法打开应用数据",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("数据存储打开或升级未完成。应用不会清空或重建原库。请保留应用和原有数据，关闭后重试；若仍失败，请先备份应用数据再检查。不要卸载应用或清空数据。")
                )
            }
        }
    }
}

@MainActor
private final class RoomMarkerAppServices {
    let modelContainer: ModelContainer
    let cameraService: SystemCameraService
    let photoStorage: LocalPhotoFileStore
    let snapshotService: SensorSnapshotService
    let sensorHub: SensorHub
    let recordingCoordinator: RecordingCoordinator

    init() throws {
        let container = try RoomMarkerModelContainer.make()
        let locationService = CoreLocationSensorService()
        let motionManager = CMMotionManager()
        let hub = SensorHub(locationService: locationService,
                            magnetometerService: CoreMotionMagnetometerService(manager: motionManager))
        let backgroundSession = CoreLocationBackgroundSession(locationService: locationService)
        let store = SwiftDataRecordingStore(context: container.mainContext)
        let photos = try LocalPhotoFileStore()
        modelContainer = container
        cameraService = SystemCameraService()
        photoStorage = photos
        snapshotService = SensorSnapshotService(hub: hub)
        sensorHub = hub
        recordingCoordinator = RecordingCoordinator(
            hub: hub,
            persistence: store,
            mediaPersistence: store,
            photoStorage: photos,
            backgroundSession: backgroundSession,
            rawIMU: RawIMURecorder(service: CoreMotionRawIMUService(manager: motionManager), persistence: store)
        )
        let referencedPaths = Set(try container.mainContext.fetch(FetchDescriptor<TrackPhoto>()).map(\.filePath))
        recordingCoordinator.retryPhotoCleanup(protecting: referencedPaths)
        try? ExportTemporaryCleaner().removeStaleOwnedExports()
    }
}
