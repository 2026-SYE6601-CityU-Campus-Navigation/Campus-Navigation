import SwiftData
import SwiftUI

@main
struct RoomMarkerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try RoomMarkerModelContainer.make()
        } catch {
            fatalError("Unable to create RoomMarker data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            FoundationReadyView()
        }
        .modelContainer(modelContainer)
    }
}
