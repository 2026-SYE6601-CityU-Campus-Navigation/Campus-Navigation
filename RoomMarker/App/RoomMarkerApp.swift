import SwiftData
import SwiftUI

@main
struct RoomMarkerApp: App {
    private let modelContainer: ModelContainer
    private let cameraService: SystemCameraService
    @State private var sensorHub: SensorHub
    @State private var recordingCoordinator: RecordingCoordinator

    init() {
        do {
            let container = try RoomMarkerModelContainer.make()
            let hub = SensorHub()
            let recordingStore = SwiftDataRecordingStore(context: container.mainContext)
            let photoStorage = try LocalPhotoFileStore()
            modelContainer = container
            cameraService = SystemCameraService()
            _sensorHub = State(initialValue: hub)
            _recordingCoordinator = State(initialValue: RecordingCoordinator(
                hub: hub,
                persistence: recordingStore,
                mediaPersistence: recordingStore,
                photoStorage: photoStorage
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
                cameraService: cameraService
            )
        }
        .modelContainer(modelContainer)
    }
}
