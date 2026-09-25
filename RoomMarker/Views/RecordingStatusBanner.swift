import SwiftUI

struct RecordingStatusBanner: View {
    let coordinator: RecordingCoordinator
    let cameraService: any CameraServicing

    @State private var isShowingTagSheet = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoNote = false
    @State private var pendingCapture: CameraCaptureOutcome?
    @State private var message: String?

    var body: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .preparing:
            statusCard(title: "正在准备轨迹…", showsProgress: true)
        case .recording:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(backgroundTitle, systemImage: "location.fill")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text(recordingSummary(at: context.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(backgroundExplanation)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("停止", role: .destructive) {
                            Task { await stop() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    HStack(spacing: 10) {
                        Button {
                            isShowingTagSheet = true
                        } label: {
                            Label("添加标签", systemImage: "tag")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button(action: beginPhotoCapture) {
                            Label("拍照", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .background(.regularMaterial)
            }
            .sheet(isPresented: $isShowingTagSheet) {
                TrackTagCaptureView(coordinator: coordinator)
            }
            .fullScreenCover(isPresented: $isShowingCamera, onDismiss: presentPhotoNoteIfNeeded) {
                CameraCaptureView { outcome in
                    pendingCapture = outcome
                    isShowingCamera = false
                    if case let .failed(reason) = outcome {
                        message = "拍照失败：\(reason)"
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingPhotoNote) {
                if case let .success(jpegData, capturedAt) = pendingCapture {
                    PhotoNoteView(jpegData: jpegData) { note in
                        savePhoto(data: jpegData, capturedAt: capturedAt, note: note)
                    } onDiscard: {
                        pendingCapture = nil
                    }
                }
            }
            .alert("照片", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "未知错误")
            }
        case .stopping:
            statusCard(title: "正在保存并停止…", showsProgress: true)
        case let .failed(message, _):
            HStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("关闭") {
                    Task { await coordinator.resetFailure() }
                }
            }
            .padding(12)
            .background(.regularMaterial)
        }
    }

    private func statusCard(title: String, showsProgress: Bool) -> some View {
        HStack(spacing: 10) {
            if showsProgress { ProgressView() }
            Text(title).font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func recordingSummary(at date: Date) -> String {
        guard let track = coordinator.activeTrack else { return "" }
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        let elapsed = RecordingElapsedTime.seconds(startedAt: track.startedAt, now: nowMs)
        return "\(track.name) · \(formatDuration(elapsed)) · \(coordinator.currentSampleCount) 个采样"
    }

    private var backgroundTitle: String {
        coordinator.backgroundStatus == .active ? "正在记录 · 后台定位已启用" : "正在记录 · 仅前台"
    }

    private var backgroundExplanation: String {
        switch coordinator.backgroundStatus {
        case .active:
            "退到后台后，iOS 允许时会继续定位；系统会显示定位指示，耗电可能增加。停止轨迹即停止后台定位。"
        case .unavailable(.authorizationPending):
            "等待前台定位授权；在授权生效前不会声称后台记录可用。"
        case .unavailable(.authorizationDenied):
            "定位权限已拒绝；轨迹仍可记录时间点，但后台定位不可用。"
        case .unavailable(.authorizationRestricted):
            "系统限制了定位；后台定位不可用。"
        case .unavailable(.backgroundModeMissing):
            "后台定位能力不可用；轨迹仅在应用可执行时采样。"
        case .inactive:
            "后台定位未启用。"
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }

    private func stop() async {
        do {
            try await coordinator.stop()
        } catch {
            // The coordinator publishes the failed state and its message.
        }
    }

    private func beginPhotoCapture() {
        Task {
            let authorization: CameraAuthorizationState
            if cameraService.authorizationState == .notDetermined {
                authorization = await cameraService.requestAuthorization()
            } else {
                authorization = cameraService.authorizationState
            }

            switch authorization {
            case .authorized:
                guard cameraService.isCameraAvailable else {
                    pendingCapture = .unavailable
                    _ = try? coordinator.handlePhotoCapture(.unavailable)
                    message = "此设备或模拟器没有可用的相机。未创建照片记录。"
                    return
                }
                pendingCapture = nil
                isShowingCamera = true
            case .denied:
                message = "相机权限已被拒绝。可在系统设置中允许 RoomMarker 使用相机。"
            case .restricted:
                message = "此设备限制了相机访问。未创建照片记录。"
            case .notDetermined:
                message = "尚未获得相机权限。未创建照片记录。"
            }
        }
    }

    private func presentPhotoNoteIfNeeded() {
        guard case .success = pendingCapture else {
            if case .cancelled = pendingCapture {
                _ = try? coordinator.handlePhotoCapture(.cancelled)
            }
            pendingCapture = nil
            return
        }
        isShowingPhotoNote = true
    }

    private func savePhoto(data: Data, capturedAt: Int64, note: String) {
        do {
            try coordinator.handlePhotoCapture(
                .success(jpegData: data, capturedAt: capturedAt),
                note: note
            )
            pendingCapture = nil
        } catch {
            pendingCapture = nil
            message = error.localizedDescription
        }
    }
}
