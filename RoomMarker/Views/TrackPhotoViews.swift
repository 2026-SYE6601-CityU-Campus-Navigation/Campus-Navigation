import SwiftUI
import UIKit

struct TrackPhotoThumbnailView: View {
    let photo: TrackPhoto
    let coordinator: RecordingCoordinator

    @State private var content: PhotoContent?

    var body: some View {
        Group {
            if let image = content?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text(statusText)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: photo.filePath) {
            content = coordinator.loadPhotoContent(photo)
        }
    }

    private var statusText: String {
        switch content?.status {
        case .corrupt: "文件损坏"
        case .missing: "文件缺失"
        case .available: ""
        case nil: "读取中"
        }
    }
}

struct TrackPhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let photo: TrackPhoto
    let coordinator: RecordingCoordinator

    @State private var content: PhotoContent?

    var body: some View {
        NavigationStack {
            Group {
                if let image = content?.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    ContentUnavailableView(
                        content?.status == .corrupt ? "照片文件已损坏" : "照片文件不存在",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("元数据仍然保留；RoomMarker 不会生成替代图像。")
                    )
                }
            }
            .navigationTitle("照片预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: photo.filePath) {
                content = coordinator.loadPhotoContent(photo)
            }
        }
    }
}
