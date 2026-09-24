import SwiftUI

struct RoomSummaryRow: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name)
            Text(room.note.isEmpty ? "\(room.markers.count) 个标记" : "\(room.note) · \(room.markers.count) 个标记")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

struct Phase2EmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        _ title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct PersistenceErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "无法保存更改",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "发生未知错误。")
        }
    }
}

extension View {
    func persistenceErrorAlert(_ message: Binding<String?>) -> some View {
        modifier(PersistenceErrorAlert(message: message))
    }
}
