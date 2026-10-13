import SwiftData
import SwiftUI
import UIKit

struct TrackTagCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.createdAt) private var areas: [Area]
    @Query(sort: \Room.createdAt) private var rooms: [Room]

    let coordinator: RecordingCoordinator
    let cameraService: any CameraServicing
    let isNode: Bool

    @State private var form: NodeCaptureForm
    @State private var errorMessage: String?
    @State private var isShowingCamera = false
    @State private var isRequestingCamera = false

    init(coordinator: RecordingCoordinator, cameraService: any CameraServicing, isNode: Bool = true) {
        self.coordinator = coordinator
        self.cameraService = cameraService
        self.isNode = isNode
        _form = State(initialValue: NodeCaptureForm(trackID: coordinator.activeTrack?.id,
                                                   initialLocation: coordinator.tagLocationContext))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isNode ? "节点" : "独立风景照片") {
                    if isNode {
                        Picker("类型", selection: $form.selectedType) {
                            ForEach(TrackTagType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    TextField("备注（可选）", text: $form.note, axis: .vertical)
                    if isNode {
                        Picker("区域", selection: $form.selectedAreaID) {
                            Text("未分区").tag(UUID?.none)
                            ForEach(areas, id: \.id) { area in
                                Text(area.name).tag(Optional(area.id))
                            }
                            if let id = form.selectedAreaID, !areas.contains(where: { $0.id == id }) {
                                Text("所选区域不可用（请重新选择）").tag(Optional(id))
                            }
                        }
                        TextField("楼层（可选，如 1/F、B1）", text: $form.floor)
                        NodeRoomPicker(rooms: rooms, areaID: form.selectedAreaID, type: form.selectedType,
                                       roomID: $form.selectedRoomID, doorRole: $form.doorRole)
                    }
                }
                Section("照片（必需）") {
                    if let capture = form.capture, let image = UIImage(data: capture.jpegData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                        Text("照片已采集；时间和可用传感器值已冻结。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let accuracy = capture.metadata.accuracy {
                            LabeledContent("水平精度", value: "\(accuracy.formatted()) m")
                        }
                        if let pressure = capture.metadata.pressureHpa {
                            LabeledContent("气压", value: "\(pressure.formatted()) hPa")
                        }
                    }
                    Button(form.capture == nil ? "拍摄照片" : "重新拍摄", action: beginCapture)
                        .disabled(isRequestingCamera)
                }

                Section {
                    Text(isNode
                         ? "一个新节点必须绑定一张照片。取消或失败不会创建独立标签；保存失败可重试。区域与楼层只记录在节点上。"
                         : "独立风景照片不绑定节点。不可用的传感器值保持为空。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNode ? "采集节点" : "拍摄风景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(form.capture == nil || isRequestingCamera)
                }
            }
            .interactiveDismissDisabled(form.capture != nil)
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { outcome in
                    isShowingCamera = false
                    do {
                        try form.receive(coordinator.freezePhotoCapture(outcome))
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .ignoresSafeArea()
            }
            .alert("无法完成采集", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        do {
            let request = try form.request(availableAreaIDs: Set(areas.map(\.id)), isNode: isNode, rooms: rooms)
            if isNode {
                try coordinator.saveNode(
                    capture: request.capture, type: request.type, note: request.note,
                    location: request.location, roomSelection: request.roomSelection
                )
            } else {
                try coordinator.saveScenery(capture: request.capture, note: request.note)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginCapture() {
        guard !isRequestingCamera else { return }
        isRequestingCamera = true
        Task {
            defer { isRequestingCamera = false }
            do {
                try await NodeCameraAccess.authorize(cameraService)
                isShowingCamera = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
