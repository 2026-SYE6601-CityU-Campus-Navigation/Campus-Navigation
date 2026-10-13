import SwiftData
import SwiftUI

struct TrackDetailView: View {
    @Query(sort: \Room.createdAt) private var rooms: [Room]
    @Environment(\.dismiss) private var dismiss
    @Bindable var track: Track
    @Query(sort: \Area.createdAt) private var areas: [Area]
    let coordinator: RecordingCoordinator

    @State private var isConfirmingDeletion = false
    @State private var isConfirmingRecoveryFinalization = false
    @State private var tagPendingDeletion: TrackTag?
    @State private var photoPendingDeletion: TrackPhoto?
    @State private var previewPhoto: TrackPhoto?
    @State private var errorMessage: String?
    @State private var editingTag: TrackTag?
    @State private var isShowingGallery = false

    private var tags: [TrackTag] {
        track.tags.sorted { $0.timeMs < $1.timeMs }
    }

    private var photos: [TrackPhoto] {
        track.photos.sorted { $0.timeMs < $1.timeMs }
    }

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("范围", value: "全局轨迹 · 按标签记录区域")
                if !track.isGlobalRecording {
                    LabeledContent("旧归属（仅历史信息）", value: track.area?.name ?? track.legacyAreaName ?? "未记录")
                }
                LabeledContent("状态", value: statusText)
                LabeledContent("开始", value: formatDate(track.startedAt))
                LabeledContent("结束", value: track.endedAt.map(formatDate) ?? "未完整结束")
                LabeledContent("采样点", value: "\(track.pointCount)")
                LabeledContent("节点 / 历史标签", value: "\(tags.count)")
                LabeledContent("照片", value: "\(photos.count)")
                LabeledContent("环境段", value: "\(track.segments.count)")
                LabeledContent("拐点", value: "\(track.corners.count)")
                if canFinalizeInterrupted {
                    Button("结束中断轨迹") {
                        isConfirmingRecoveryFinalization = true
                    }
                }
            }

            Track3DView(track: track)

            TrackStructureDetailSections(track: track, coordinator: coordinator)
            TrackIMUDetailSection(track: track, coordinator: coordinator)
            TrackRoomGenerationSection(track: track, areas: areas, rooms: rooms)

            Section("节点 / 历史标签") {
                ForEach(tags, id: \.id) { tag in
                    tagRow(tag)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                tagPendingDeletion = tag
                            }
                            Button("编辑位置") { editingTag = tag }
                                .tint(.blue)
                        }
                }
                if tags.isEmpty {
                    Text("还没有标签。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("照片") {
                ForEach(photos, id: \.id) { photo in
                    Button {
                        previewPhoto = photo
                    } label: {
                        photoRow(photo)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(photo.isNodePhoto ? "删除节点" : "删除", role: .destructive) {
                            if photo.isNodePhoto {
                                guard let tag = tags.first(where: { $0.id == photo.tagID && $0.isNode }),
                                      (try? NodePhotoAssociation.photo(for: tag))?.id == photo.id else {
                                    errorMessage = NodeCaptureError.invalidAssociation.localizedDescription
                                    return
                                }
                                tagPendingDeletion = tag
                            } else {
                                photoPendingDeletion = photo
                            }
                        }
                    }
                }
                if photos.isEmpty {
                    Text("还没有照片。")
                        .foregroundStyle(.secondary)
                }
            }

            TrackPointDetailSection(track: track)
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !photos.isEmpty {
                    Button("相册", systemImage: "photo.on.rectangle.angled") { isShowingGallery = true }
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .disabled(coordinator.isActive(track))
            }
        }
        .sheet(isPresented: $isShowingGallery) {
            TrackGalleryView(track: track, coordinator: coordinator)
        }
        .confirmationDialog(
            "结束这条中断轨迹？",
            isPresented: $isConfirmingRecoveryFinalization,
            titleVisibility: .visible
        ) {
            Button("以当前时间结束", action: finalizeInterruptedTrack)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有您确认后才会写入明确的结束时间；应用不会补造中断期间的采样点。")
        }
        .confirmationDialog(
            "删除轨迹“\(track.name)”？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("删除轨迹及其数据", role: .destructive, action: deleteTrack)
            Button("取消", role: .cancel) {}
        } message: {
            Text("采样点、原始 IMU、拐点、环境段、标签、照片元数据和 RoomMarker 拥有的照片文件都会删除。")
        }
        .confirmationDialog(
            "删除标签“\(tagPendingDeletion?.tagTypeRawValue ?? "")”？",
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { if !$0 { tagPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tagPendingDeletion?.isNode == true ? "删除节点及其照片" : "删除历史标签",
                   role: .destructive, action: deletePendingTag)
            Button("取消", role: .cancel) { tagPendingDeletion = nil }
        } message: {
            Text(tagPendingDeletion?.isNode == true
                 ? "节点和唯一关联的照片元数据及图像文件一起删除；其他照片和历史标签不受影响。"
                 : "只删除此历史独立标签，不会猜测或删除任何照片。")
        }
        .confirmationDialog(
            "删除这张照片？",
            isPresented: Binding(
                get: { photoPendingDeletion != nil },
                set: { if !$0 { photoPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除照片及文件", role: .destructive, action: deletePendingPhoto)
            Button("取消", role: .cancel) { photoPendingDeletion = nil }
        } message: {
            Text("照片记录和 RoomMarker 应用存储中的图像文件都会删除。")
        }
        .sheet(isPresented: Binding(
            get: { editingTag != nil },
            set: { if !$0 { editingTag = nil } }
        )) {
            if let editingTag { TrackTagLocationEditorView(tag: editingTag) }
        }
        .sheet(isPresented: Binding(
            get: { previewPhoto != nil },
            set: { if !$0 { previewPhoto = nil } }
        )) {
            if let previewPhoto {
                TrackPhotoPreviewView(photo: previewPhoto, coordinator: coordinator)
            }
        }
        .alert("操作未完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: TrackTag) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tag.tagTypeRawValue).font(.headline)
            Text(tag.isNode ? "节点 · 关联照片" : "历史独立标签").foregroundStyle(.secondary)
            if tag.isNode {
                if let photo = try? NodePhotoAssociation.photo(for: tag) {
                    Button {
                        previewPhoto = photo
                    } label: {
                        TrackPhotoThumbnailView(photo: photo, coordinator: coordinator)
                    }.buttonStyle(.plain)
                } else {
                    Text("节点照片关联异常，请保留数据检查。").foregroundStyle(.red)
                }
            }
            Text("\(TrackAreaIndex.areaLabel(for: tag, areas: areas)) · 楼层 \(tag.floor.isEmpty ? "未记录" : tag.floor)")
                .foregroundStyle(.secondary)
            if tag.isNode { Text(NodeRoomBinding.label(for: tag, rooms: rooms)).foregroundStyle(.secondary) }
            if !tag.note.isEmpty { Text(tag.note) }
            Text(formatDate(tag.timeMs)).foregroundStyle(.secondary)
            locationLine(latitude: tag.latitude, longitude: tag.longitude)
            optionalLine("海拔", value: tag.altitude, unit: "m")
            optionalLine("水平精度", value: tag.accuracy, unit: "m")
            optionalLine("气压", value: tag.pressureHpa, unit: "hPa")
            optionalLine("朝向", value: tag.headingDeg, unit: "°")
        }
        .font(.caption)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func photoRow(_ photo: TrackPhoto) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TrackPhotoThumbnailView(photo: photo, coordinator: coordinator)
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(photo.timeMs)).font(.subheadline)
                Text(photo.isNodePhoto ? "节点照片" : (photo.kindRawValue == "scenery" ? "独立风景照片" : "历史独立照片"))
                    .foregroundStyle(.secondary)
                if !photo.note.isEmpty { Text(photo.note) }
                locationLine(latitude: photo.latitude, longitude: photo.longitude)
                optionalLine("海拔", value: photo.altitude, unit: "m")
                optionalLine("水平精度", value: photo.accuracy, unit: "m")
                optionalLine("气压", value: photo.pressureHpa, unit: "hPa")
                optionalLine("朝向", value: photo.headingDeg, unit: "°")
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func optionalLine(_ label: String, value: Double?, unit: String) -> some View {
        if let value {
            Text("\(label) \(format(value)) \(unit)")
        }
    }

    @ViewBuilder
    private func locationLine(latitude: Double?, longitude: Double?) -> some View {
        if let latitude, let longitude {
            Text("位置 \(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))")
        }
    }

    private var statusText: String {
        if coordinator.isActive(track) {
            return coordinator.backgroundStatus == .active
                ? "进行中（后台定位由 iOS 调度）"
                : "进行中（后台定位不可用）"
        }
        return track.endedAt == nil ? "未完整结束" : "已结束"
    }

    private var canFinalizeInterrupted: Bool {
        track.endedAt == nil && !coordinator.isActive(track)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func formatDate(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .standard)
    }

    private func deleteTrack() {
        do {
            try coordinator.delete(track)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finalizeInterruptedTrack() {
        do {
            try coordinator.finalizeInterrupted(track)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingTag() {
        guard let tagPendingDeletion else { return }
        do {
            try coordinator.deleteTag(tagPendingDeletion)
            self.tagPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingPhoto() {
        guard let photoPendingDeletion else { return }
        do {
            try coordinator.deletePhoto(photoPendingDeletion)
            self.photoPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
