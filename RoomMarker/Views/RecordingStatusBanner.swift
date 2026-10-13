import SwiftUI

struct RecordingStatusBanner: View {
    let coordinator: RecordingCoordinator
    let cameraService: any CameraServicing

    @State private var isShowingTagSheet = false
    @State private var isShowingPhotoNote = false
    @State private var structureMessage: String?

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
                            Label("采集节点", systemImage: "tag")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button { isShowingPhotoNote = true } label: {
                            Label("拍摄风景", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(TrackEnvironment.allCases, id: \.self) { environment in
                                Button(environment.title) { changeEnvironment(environment) }
                            }
                        } label: {
                            Label("环境：\(coordinator.activeSegment?.environment?.title ?? "不可用")",
                                  systemImage: "building.2.crop.circle")
                        }
                        .disabled(coordinator.activeSegment == nil)
                        Spacer()
                        Button {
                            do {
                                _ = try coordinator.captureCorner()
                            } catch { structureMessage = error.localizedDescription }
                        } label: {
                            Label("采集拐点", systemImage: "arrow.turn.up.right")
                        }
                        .disabled(coordinator.activeSegment == nil)
                    }
                    .font(.subheadline)
                    if let count = coordinator.activeTrack?.corners.count, count > 0 {
                        Text("已保存 \(count) 个拐点").font(.caption).foregroundStyle(.secondary)
                    }
                    if coordinator.activeTrack?.rawIMURequested == true, let imu = coordinator.rawIMU {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("原始 IMU · 已接收 \(imu.acceptedCount) 条 · 待存 \(imu.pendingCount) 条")
                            Text("加速度：\(imu.status.accelerometer.title) · 角速度：\(imu.status.gyroscope.title)")
                            if let error = imu.errorMessage {
                                Text(error).foregroundStyle(.red)
                                Button("重试 IMU 保存") {
                                    do { try imu.retry() } catch { structureMessage = error.localizedDescription }
                                }
                            }
                        }.font(.caption)
                    }
                }
                .padding(12)
                .background(.regularMaterial)
            }
            .sheet(isPresented: $isShowingTagSheet) {
                TrackTagCaptureView(coordinator: coordinator, cameraService: cameraService)
            }
            .sheet(isPresented: $isShowingPhotoNote) {
                TrackTagCaptureView(coordinator: coordinator, cameraService: cameraService, isNode: false)
            }
            .alert("采集未完成", isPresented: Binding(
                get: { structureMessage != nil },
                set: { if !$0 { structureMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(structureMessage ?? "未知错误")
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
                Button(coordinator.activeTrack?.rawIMURequested == true ? "重试保存并关闭" : "关闭") {
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

    private func changeEnvironment(_ environment: TrackEnvironment) {
        do {
            try coordinator.changeEnvironment(to: environment)
        } catch {
            structureMessage = error.localizedDescription
        }
    }
}
