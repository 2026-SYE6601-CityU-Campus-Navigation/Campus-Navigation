import Foundation
import Observation

@MainActor
@Observable
final class RawIMURecorder {
    private(set) var status = RawIMUStatus()
    // These change at sensor rate. Views sample them on their own 1 Hz timeline;
    // they must not invalidate the surrounding navigation tree for every event.
    @ObservationIgnored private(set) var acceptedCount = 0
    private(set) var errorMessage: String?
    @ObservationIgnored private(set) var lastReadings: [RawIMUKind: RawIMUSample] = [:]
    @ObservationIgnored private(set) var savedSummary = RawIMUSavedSummary()
    @ObservationIgnored private let service: any RawIMUServicing
    @ObservationIgnored private let persistence: any RawIMUPersisting
    @ObservationIgnored private let now: @MainActor @Sendable () -> Int64
    @ObservationIgnored private let uptime: @MainActor @Sendable () -> Double
    @ObservationIgnored private var track: Track?
    @ObservationIgnored private var pending: [RawIMUSample] = []
    @ObservationIgnored private var batchID = UUID()
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var anchorWallMs: Int64 = 0
    @ObservationIgnored private var anchorUptime: Double = 0
    @ObservationIgnored private var isBackground = false
    @ObservationIgnored private var finishing = false

    var canStart: Bool { track == nil && pending.isEmpty }
    var pendingCount: Int { pending.count }
    var latestTimeMs: Int64? { lastReadings.values.map(\.timeMs).max() }

    init(
        service: any RawIMUServicing, persistence: any RawIMUPersisting,
        now: @escaping @MainActor @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        uptime: @escaping @MainActor @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.service = service
        self.persistence = persistence
        self.now = now
        self.uptime = uptime
    }

    func begin(for track: Track) throws {
        guard canStart, track.rawIMURequested, track.endedAt == nil else { throw RawIMUError.pendingSave }
        self.track = track
        status = RawIMUStatus()
        acceptedCount = 0
        lastReadings = [:]
        savedSummary = RawIMUSavedSummary()
        errorMessage = nil
        anchorWallMs = now()
        anchorUptime = uptime()
        finishing = false
        isBackground = false
        batchID = UUID()
        do { try startService() } catch { suspendAfterFailure(error) }
    }

    func pauseForBackground() {
        guard track != nil, !isBackground, !finishing else { return }
        isBackground = true
        stopService()
        markActiveChannels(.paused)
        do { try flush() } catch { suspendAfterFailure(error) }
    }

    func resumeForeground() {
        guard track != nil, isBackground, !finishing else { return }
        isBackground = false
        guard errorMessage == nil else { return }
        do { try startService() } catch { suspendAfterFailure(error) }
    }

    func stopAndFlush() throws {
        guard track != nil else { return }
        finishing = true
        stopService()
        markActiveChannels(.stopped)
        do {
            try flush()
            errorMessage = nil
            track = nil
        } catch {
            suspendAfterFailure(error)
            throw error
        }
    }

    func retry() throws {
        guard track != nil else { return }
        do {
            try flush()
            errorMessage = nil
            if finishing { track = nil }
            else if !isBackground { try startService() }
        } catch {
            suspendAfterFailure(error)
            throw error
        }
    }

    private func startService() throws {
        token = UUID()
        let currentToken = token
        service.start(interval: RawIMUPolicy.interval) { [weak self] event in
            guard let self, self.token == currentToken, self.track != nil,
                  !self.isBackground, !self.finishing, self.errorMessage == nil else { return }
            self.receive(event)
        }
        try flush()
    }

    private func stopService() {
        token = UUID()
        service.stop()
    }

    private func markActiveChannels(_ state: RawIMUChannelState) {
        for kind in RawIMUKind.allCases where [.waiting, .receiving, .paused].contains(status[kind]) {
            status[kind] = state
        }
    }

    private func receive(_ event: RawIMUEvent) {
        switch event {
        case let .state(kind, state): status[kind] = state
        case let .reading(reading): accept(reading)
        }
    }

    private func accept(_ reading: RawIMUReading) {
        guard let track else { return }
        let value = Double(anchorWallMs) + (reading.sensorTimeSeconds - anchorUptime) * 1000
        guard reading.sensorTimeSeconds.isFinite, reading.sensorTimeSeconds >= anchorUptime,
              [.waiting, .receiving].contains(status[reading.kind]),
              reading.sensorTimeSeconds <= uptime() + 0.1,
              reading.x.isFinite, reading.y.isFinite, reading.z.isFinite,
              value.isFinite, value.rounded() >= Double(Int64.min), value.rounded() < Double(Int64.max),
              lastReadings[reading.kind].map({ reading.sensorTimeSeconds > $0.sensorTimeSeconds }) ?? true else {
            status.rejectedCount += 1
            return
        }
        let timeMs = Int64(value.rounded())
        guard let segment = track.segments.first(where: {
            $0.track?.id == track.id && timeMs >= $0.startedAt && ($0.endedAt.map { timeMs < $0 } ?? true)
        }) else {
            status.rejectedCount += 1
            return
        }
        let sample = RawIMUSample(kind: reading.kind, sensorTimeSeconds: reading.sensorTimeSeconds,
                                  timeMs: timeMs, receivedAtMs: now(), segmentID: segment.id,
                                  x: reading.x, y: reading.y, z: reading.z)
        pending.append(sample)
        lastReadings[reading.kind] = sample
        acceptedCount += 1
        if status[reading.kind] != .receiving { status[reading.kind] = .receiving }
        if pending.count >= RawIMUPolicy.batchSize {
            do { try flush() } catch { suspendAfterFailure(error) }
        }
    }

    private func flush() throws {
        guard let track else { return }
        try persistence.saveIMU(id: batchID, samples: pending, status: status, for: track)
        // Advance only after success, including an idempotent retry of a batch
        // that committed before reporting failure. Never count that tail twice.
        savedSummary.append(pending)
        pending.removeAll(keepingCapacity: true)
        batchID = UUID()
    }

    private func suspendAfterFailure(_ error: Error) {
        stopService()
        errorMessage = "原始 IMU 保存未完成，已暂停 IMU 并保留 \(pending.count) 条待存记录。请重试保存。"
    }
}
