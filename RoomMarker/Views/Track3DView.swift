import SwiftUI

struct Track3DView: View {
    @Bindable var track: Track
    @State private var yaw = -35.0
    @State private var pitch = 42.0
    @State private var zoom = 1.0
    @State private var dragOrigin: (yaw: Double, pitch: Double)?
    @State private var zoomOrigin: Double?

    private var plan: Track3DPlan {
        Track3DPlanner.build(
            points: track.points.map {
                .init(timeMs: $0.timeMs, latitude: $0.latitude, longitude: $0.longitude,
                      altitude: $0.altitude, accuracy: $0.accuracy, pressureHpa: $0.pressureHpa)
            },
            pins: track.tags.sorted { $0.timeMs < $1.timeMs }.map {
                let parts = [$0.tagTypeRawValue, $0.floor, $0.note].filter { !$0.isEmpty }
                return .init(id: $0.id, timeMs: $0.timeMs, latitude: $0.latitude,
                             longitude: $0.longitude, accuracy: $0.accuracy,
                             label: parts.joined(separator: " · "))
            }
        )
    }

    var body: some View {
        let plan = plan
        if plan.samples.count >= 2 {
            Section("轨迹立体图") {
                HStack {
                    Button("楼盘") { yaw = -35; pitch = 42; zoom = 1 }
                    Button("侧视") { yaw = 0; pitch = 8; zoom = 1 }
                    Spacer()
                    Text(plan.heightSource.title).font(.caption).foregroundStyle(.secondary)
                }
                Canvas { context, size in draw(plan: plan, in: &context, size: size) }
                    .frame(height: 280)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .gesture(dragGesture.simultaneously(with: magnifyGesture))
                    .accessibilityLabel("可旋转缩放的轨迹立体图")
                Text("单指拖动旋转，双指缩放。精度差于 8 m 的线段变淡；差于 50 m 或缺少坐标的采样点不绘制。空心节点为按时间就近推算，并非实测位置。")
                    .font(.caption).foregroundStyle(.secondary)
                if plan.zScale < 0.999 {
                    Text("竖向显示压缩到真实比例的 \((plan.zScale * 100).formatted(.number.precision(.fractionLength(0))))%；高度数值本身未改写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if plan.omittedPointCount > 0 {
                    Text("\(plan.omittedPointCount) 个无可用定位或精度过弱的点未画入图中，原始记录仍保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = (yaw, pitch) }
                guard let origin = dragOrigin else { return }
                yaw = origin.yaw + value.translation.width * 0.35
                pitch = min(72, max(-10, origin.pitch - value.translation.height * 0.25))
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomOrigin == nil { zoomOrigin = zoom }
                zoom = min(4, max(0.5, (zoomOrigin ?? 1) * value.magnification))
            }
            .onEnded { _ in zoomOrigin = nil }
    }

    private func draw(plan: Track3DPlan, in context: inout GraphicsContext, size: CGSize) {
        let projectedSamples = plan.samples.map { project($0.position) }
        let projectedPins = plan.pins.map { ($0, project($0.position)) }
        let all = projectedSamples + projectedPins.map(\.1)
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return }
        let margin = 26.0
        let fit = min((size.width - margin * 2) / max(maxX - minX, 1),
                      (size.height - margin * 2) / max(maxY - minY, 1)) * zoom
        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: size.width / 2 + (point.x - (minX + maxX) / 2) * fit,
                    y: size.height / 2 - (point.y - (minY + maxY) / 2) * fit)
        }
        for index in plan.samples.indices.dropFirst() where !plan.samples[index].startsNewPart {
            var path = Path()
            path.move(to: screen(projectedSamples[index - 1]))
            path.addLine(to: screen(projectedSamples[index]))
            let weak = plan.samples[index - 1].weak || plan.samples[index].weak
            context.stroke(path, with: .color(.accentColor.opacity(weak ? 0.28 : 0.9)),
                           style: StrokeStyle(lineWidth: weak ? 1.5 : 2.5, lineCap: .round))
        }
        for (pin, point) in projectedPins {
            let center = screen(point)
            let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(pin.estimated ? .clear : .red))
            context.stroke(Path(ellipseIn: rect), with: .color(.red), lineWidth: 2)
            context.draw(Text(pin.label).font(.caption2).foregroundStyle(.primary),
                         at: CGPoint(x: center.x + 7, y: center.y - 9), anchor: .leading)
        }
    }

    private func project(_ point: Track3DVector) -> CGPoint {
        let y = yaw * .pi / 180
        let p = pitch * .pi / 180
        let rx = cos(y) * point.x - sin(y) * point.y
        let ry = sin(y) * point.x + cos(y) * point.y
        return CGPoint(x: rx, y: cos(p) * ry + sin(p) * point.z)
    }
}
