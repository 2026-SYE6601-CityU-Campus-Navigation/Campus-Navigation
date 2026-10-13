import SwiftData
import SwiftUI

struct PlaceRecognitionView: View {
    @Query private var tags: [TrackTag]
    @Query private var areas: [Area]
    @Query private var rooms: [Room]
    let snapshotService: any SensorSnapshotCapturing

    @State private var isCapturing = false
    @State private var snapshot: SensorSnapshot?
    @State private var result: PlaceRecognitionResult?
    @State private var errorMessage: String?

    private var landmarks: [PlaceLandmark] {
        let areaByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.name) })
        return tags.compactMap { tag in
            guard tag.isNode, let latitude = tag.latitude, let longitude = tag.longitude,
                  latitude.isFinite, longitude.isFinite,
                  tag.accuracy.map({ $0 >= 0 && $0 <= PlaceRecognitionEngine.maximumLocationAccuracy }) ?? true else {
                return nil
            }
            let room = rooms.first { $0.id == tag.roomID }
            let title = [tag.roomCodeSnapshot, tag.roomNameSnapshot,
                         tag.note.isEmpty ? tag.tagTypeRawValue : tag.note]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return PlaceLandmark(id: tag.id, label: title,
                                 areaName: tag.areaID.flatMap { areaByID[$0] } ?? "未分区",
                                 floor: tag.floor.isEmpty ? (room?.floor ?? "") : tag.floor,
                                 latitude: latitude, longitude: longitude,
                                 accuracy: tag.accuracy, pressureHpa: tag.pressureHpa)
        }
    }

    var body: some View {
        List {
            Section("iOS 地点识别") {
                Text("iOS 普通应用不能扫描附近 Wi‑Fi。本页不会伪造指纹，而是用当前 Core Location 与历史节点的坐标、精度和可用气压给出保守的最近地点估计。")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("可用历史节点", value: "\(landmarks.count)")
                Button(isCapturing ? "正在读取…" : "识别当前位置", systemImage: "location.magnifyingglass") {
                    capture()
                }
                .disabled(isCapturing)
            }

            if let snapshot {
                Section("本次观测") {
                    LabeledContent("定位", value: snapshot.latitude == nil ? "不可用" : "可用")
                    if let accuracy = snapshot.accuracy {
                        LabeledContent("水平精度", value: accuracy.formatted(.number.precision(.fractionLength(1))) + " m")
                    }
                    if let pressure = snapshot.pressureHpa {
                        LabeledContent("气压", value: pressure.formatted(.number.precision(.fractionLength(1))) + " hPa")
                    }
                    Text("不可用字段保持为空，不用 0 或上次数据代替。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let result {
                Section("识别结果") {
                    if let accepted = result.accepted {
                        Label(accepted.landmark.label, systemImage: "checkmark.location.fill")
                            .font(.headline).foregroundStyle(.green)
                        Text([accepted.landmark.areaName, accepted.landmark.floor]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                        LabeledContent("约距节点", value: meters(accepted.distanceMeters))
                    } else {
                        Label("未确认具体地点", systemImage: "location.slash")
                            .foregroundStyle(.orange)
                    }
                    Text(result.explanation).font(.footnote).foregroundStyle(.secondary)
                }
                if !result.candidates.isEmpty {
                    Section("最近候选") {
                        ForEach(result.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.landmark.label)
                                Text("\(candidate.landmark.areaName)\(candidate.landmark.floor.isEmpty ? "" : " · \(candidate.landmark.floor)") · \(meters(candidate.distanceMeters))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let difference = candidate.pressureDifferenceHpa {
                                    Text("气压差 \(difference.formatted(.number.precision(.fractionLength(1)))) hPa")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("我在哪")
        .navigationBarTitleDisplayMode(.inline)
        .persistenceErrorAlert($errorMessage)
    }

    private func capture() {
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let captured = try await snapshotService.capture()
                snapshot = captured
                if let latitude = captured.latitude, let longitude = captured.longitude {
                    result = PlaceRecognitionEngine.recognize(latitude: latitude, longitude: longitude,
                                                              accuracy: captured.accuracy,
                                                              pressureHpa: captured.pressureHpa,
                                                              landmarks: landmarks)
                } else {
                    result = .init(candidates: [], accepted: nil,
                                   explanation: "本次没有可用定位，未生成地点结果。")
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func meters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " m"
    }
}
