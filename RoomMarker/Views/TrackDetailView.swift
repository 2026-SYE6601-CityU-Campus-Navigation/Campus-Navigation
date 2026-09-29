import SwiftUI

struct TrackDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var track: Track
    let coordinator: RecordingCoordinator

    @State private var isConfirmingDeletion = false
    @State private var isConfirmingRecoveryFinalization = false
    @State private var tagPendingDeletion: TrackTag?
    @State private var photoPendingDeletion: TrackPhoto?
    @State private var previewPhoto: TrackPhoto?
    @State private var errorMessage: String?

    private var points: [TrackPoint] {
        track.points.sorted { $0.timeMs < $1.timeMs }
    }

    private var tags: [TrackTag] {
        track.tags.sorted { $0.timeMs < $1.timeMs }
    }

    private var photos: [TrackPhoto] {
        track.photos.sorted { $0.timeMs < $1.timeMs }
    }

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("区域", value: track.area?.name ?? "未分区")
                LabeledContent("状态", value: statusText)
                LabeledContent("开始", value: formatDate(track.startedAt))
                LabeledContent("结束", value: track.endedAt.map(formatDate) ?? "未完整结束")
                LabeledContent("采样点", value: "\(track.pointCount)")
                LabeledContent("标签", value: "\(tags.count)")
                LabeledContent("照片", value: "\(photos.count)")
                if canFinalizeInterrupted {
                    Button("结束中断轨迹") {
                        isConfirmingRecoveryFinalization = true
                    }
                }
            }

            Section("标签") {
                ForEach(tags, id: \.id) { tag in
                    tagRow(tag)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                tagPendingDeletion = tag
                            }
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
                        Button("删除", role: .destructive) {
                            photoPendingDeletion = photo
                        }
                    }
                }
                if photos.isEmpty {
                    Text("还没有照片。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("采样点") {
                ForEach(points, id: \.id) { point in
                    pointRow(point)
                }
                if points.isEmpty {
                    Text("还没有已保存的采样点。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("删除", systemImage: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .disabled(coordinator.isActive(track))
            }
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
            Text("采样点、标签、照片元数据和 RoomMarker 拥有的照片文件都会删除。")
        }
        .confirmationDialog(
            "删除标签“\(tagPendingDeletion?.tagTypeRawValue ?? "")”？",
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { if !$0 { tagPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除标签", role: .destructive, action: deletePendingTag)
            Button("取消", role: .cancel) { tagPendingDeletion = nil }
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
            get: { previewPhoto != nil },
            set: { if !$0 { previewPhoto = nil } }
        )) {
            if let previewPhoto {
                TrackPhotoPreviewView(photo: previewPhoto, coordinator: coordinator)
            }
        }
        .alert("无法删除轨迹", isPresented: Binding(
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
            if !tag.note.isEmpty { Text(tag.note) }
            Text(formatDate(tag.timeMs)).foregroundStyle(.secondary)
            locationLine(latitude: tag.latitude, longitude: tag.longitude)
            optionalLine("海拔", value: tag.altitude, unit: "m")
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
                if !photo.note.isEmpty { Text(photo.note) }
                locationLine(latitude: photo.latitude, longitude: photo.longitude)
                optionalLine("海拔", value: photo.altitude, unit: "m")
                optionalLine("朝向", value: photo.headingDeg, unit: "°")
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func pointRow(_ point: TrackPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(point.timeMs)).font(.subheadline)
            if let latitude = point.latitude, let longitude = point.longitude {
                Text("位置 \(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))")
            }
            optionalLine("海拔", value: point.altitude, unit: "m")
            optionalLine("水平精度", value: point.accuracy, unit: "m")
            optionalLine("气压", value: point.pressureHpa, unit: "hPa")
            optionalLine("朝向", value: point.headingDeg, unit: "°")
            if let x = point.magneticX, let y = point.magneticY, let z = point.magneticZ {
                Text("磁场 X \(format(x)) / Y \(format(y)) / Z \(format(z)) µT")
            }
            if hasNoHardwareReading(point) {
                Text("此采样点没有可用的硬件读数。")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
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

    private func hasNoHardwareReading(_ point: TrackPoint) -> Bool {
        point.latitude == nil
            && point.longitude == nil
            && point.altitude == nil
            && point.accuracy == nil
            && point.pressureHpa == nil
            && point.magneticX == nil
            && point.magneticY == nil
            && point.magneticZ == nil
            && point.headingDeg == nil
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
