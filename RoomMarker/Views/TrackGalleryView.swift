import SwiftUI

struct TrackGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var track: Track
    let coordinator: RecordingCoordinator
    @State private var selectedID: UUID?

    private var photos: [TrackPhoto] {
        track.photos.sorted { ($0.timeMs, $0.id.uuidString) < ($1.timeMs, $1.id.uuidString) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedID, photos.contains(where: { $0.id == selectedID }) {
                    TabView(selection: $selectedID) {
                        ForEach(photos, id: \.id) { photo in
                            TrackGalleryPage(photo: photo, tag: track.tags.first { $0.id == photo.tagID },
                                             coordinator: coordinator)
                                .tag(Optional(photo.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                } else {
                    galleryGrid
                }
            }
            .navigationTitle(selectedID == nil ? "轨迹相册" : "照片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedID == nil ? "完成" : "返回") {
                        if selectedID == nil { dismiss() } else { selectedID = nil }
                    }
                }
            }
        }
    }

    private var galleryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                group("节点照片", photos.filter(\.isNodePhoto))
                group("独立风景", photos.filter { $0.kindRawValue == "scenery" && !$0.isNodePhoto })
                group("历史独立照片", photos.filter { !$0.isNodePhoto && $0.kindRawValue != "scenery" })
            }
            .padding()
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ values: [TrackPhoto]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(title)（\(values.count)）").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    ForEach(values, id: \.id) { photo in
                        Button { selectedID = photo.id } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                TrackPhotoThumbnailView(photo: photo, coordinator: coordinator)
                                    .frame(maxWidth: .infinity)
                                Text(photo.note.isEmpty ? format(photo.timeMs) : photo.note)
                                    .font(.caption).lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func format(_ timeMs: Int64) -> String {
        Date(timeIntervalSince1970: Double(timeMs) / 1_000).formatted(date: .omitted, time: .shortened)
    }
}

private struct TrackGalleryPage: View {
    let photo: TrackPhoto
    let tag: TrackTag?
    let coordinator: RecordingCoordinator
    @State private var content: PhotoContent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if let image = content?.image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        ContentUnavailableView(content?.status == .corrupt ? "照片损坏" : "照片不可用",
                                               systemImage: "photo.badge.exclamationmark")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260)

                GroupBox("完整参数") {
                    VStack(alignment: .leading, spacing: 7) {
                        row("类别", photo.isNodePhoto ? "节点照片" : (photo.kindRawValue == "scenery" ? "独立风景" : "历史独立照片"))
                        if let tag { row("所属节点", [tag.tagTypeRawValue, tag.floor, tag.note].filter { !$0.isEmpty }.joined(separator: " · ")) }
                        row("备注", photo.note.isEmpty ? "未记录" : photo.note)
                        row("时间", Date(timeIntervalSince1970: Double(photo.timeMs) / 1_000).formatted(date: .abbreviated, time: .standard))
                        if let latitude = photo.latitude, let longitude = photo.longitude {
                            row("位置", "\(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))")
                        }
                        optional("海拔", photo.altitude, "m")
                        optional("水平精度", photo.accuracy, "m")
                        optional("气压", photo.pressureHpa, "hPa")
                        optional("朝向", photo.headingDeg, "°")
                        row("文件", photo.filePath)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .task(id: photo.filePath) { content = coordinator.loadPhotoContent(photo) }
    }

    @ViewBuilder
    private func optional(_ label: String, _ value: Double?, _ unit: String) -> some View {
        if let value { row(label, value.formatted(.number.precision(.fractionLength(2))) + " " + unit) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
}
