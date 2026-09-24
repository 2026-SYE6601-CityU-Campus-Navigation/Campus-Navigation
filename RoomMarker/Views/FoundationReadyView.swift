import SwiftUI

struct FoundationReadyView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("RoomMarker")
                .font(.largeTitle.bold())
            Text("iOS Foundation Ready")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    FoundationReadyView()
}
