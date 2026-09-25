import SwiftData
import SwiftUI

@main
struct RoomMarkerApp: App {
    private let modelContainer: ModelContainer
    private let cameraService: SystemCameraService
    private let photoStorage: LocalPhotoFileStore
    @State private var sensorHub: SensorHub
    @State private var recordingCoordinator: RecordingCoordinator

    init() {
        do {
            let container = try RoomMarkerModelContainer.make()
            let locationService = CoreLocationSensorService()
            let hub = SensorHub(locationService: locationService)
            let backgroundSession = CoreLocationBackgroundSession(
                locationService: locationService
            )
            let recordingStore = SwiftDataRecordingStore(context: container.mainContext)
            let photoStorage = try LocalPhotoFileStore()
            try? ExportTemporaryCleaner().removeStaleOwnedExports()
            modelContainer = container
            cameraService = SystemCameraService()
            self.photoStorage = photoStorage
            _sensorHub = State(initialValue: hub)
            _recordingCoordinator = State(initialValue: RecordingCoordinator(
                hub: hub,
                persistence: recordingStore,
                mediaPersistence: recordingStore,
                photoStorage: photoStorage,
                backgroundSession: backgroundSession
            ))
        } catch {
            fatalError("Unable to create RoomMarker data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AreaListView(
                sensorHub: sensorHub,
                recordingCoordinator: recordingCoordinator,
                cameraService: cameraService,
                photoStorage: photoStorage
            )
        }
        .modelContainer(modelContainer)
    }
}
