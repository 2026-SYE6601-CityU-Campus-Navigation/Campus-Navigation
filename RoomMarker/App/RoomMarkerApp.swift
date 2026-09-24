import SwiftData
import SwiftUI

@main
struct RoomMarkerApp: App {
    private let modelContainer: ModelContainer
    @State private var sensorHub: SensorHub
    @State private var recordingCoordinator: RecordingCoordinator

    init() {
        do {
            let container = try RoomMarkerModelContainer.make()
            let hub = SensorHub()
            modelContainer = container
            _sensorHub = State(initialValue: hub)
            _recordingCoordinator = State(initialValue: RecordingCoordinator(
                hub: hub,
                persistence: SwiftDataRecordingStore(context: container.mainContext)
            ))
        } catch {
            fatalError("Unable to create RoomMarker data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AreaListView(
                sensorHub: sensorHub,
                recordingCoordinator: recordingCoordinator
            )
        }
        .modelContainer(modelContainer)
    }
}
