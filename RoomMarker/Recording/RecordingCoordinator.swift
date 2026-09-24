import Foundation
import Observation

@MainActor
@Observable
final class RecordingCoordinator {
    private(set) var state: RecordingState = .idle
    private(set) var activeTrack: Track?
    private(set) var currentSampleCount = 0
    private(set) var transitionHistory: [RecordingPhase] = [.idle]

    @ObservationIgnored private let hub: any SensorHubProtocol
    @ObservationIgnored private let ticker: any RecordingTicking
    @ObservationIgnored private let persistence: any RecordingPersisting
    @ObservationIgnored private let assembler: SampleAssembler
    @ObservationIgnored private let nowMilliseconds: @MainActor @Sendable () -> Int64
    @ObservationIgnored private var pending: [TrackPointDraft] = []
    @ObservationIgnored private var lastAcceptedTickMs: Int64?

    init(
        hub: any SensorHubProtocol,
        ticker: any RecordingTicking = ForegroundRecordingTicker(),
        persistence: any RecordingPersisting,
        assembler: SampleAssembler = SampleAssembler(),
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.hub = hub
        self.ticker = ticker
        self.persistence = persistence
        self.assembler = assembler
        self.nowMilliseconds = nowMilliseconds
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var activeTrackID: UUID? {
        activeTrack?.id
    }

    func start(name: String, area: Area?) throws {
        guard state == .idle else { throw RecordingError.alreadyActive }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw RecordingError.emptyName }
        guard let area else { throw RecordingError.areaRequired }

        transition(to: .preparing)
        do {
            let track = try persistence.createTrack(
                name: trimmedName,
                area: area,
                startedAt: nowMilliseconds()
            )
            activeTrack = track
            currentSampleCount = 0
            pending.removeAll(keepingCapacity: true)
            lastAcceptedTickMs = nil

            hub.start(consumer: .recording, requestLocationAuthorization: true)
            ticker.start { [weak self] timeMs in
                guard let self else { return false }
                return self.acceptTick(timeMs)
            }
            transition(to: .recording(trackID: track.id))
        } catch {
            transition(to: .failed(message: error.localizedDescription, trackID: nil))
            throw error
        }
    }

    func stop() async throws {
        guard case let .recording(trackID) = state,
              let track = activeTrack,
              track.id == trackID else {
            throw RecordingError.notRecording
        }

        transition(to: .stopping(trackID: trackID))
        await ticker.stop()

        do {
            try flushPending(to: track)
            try persistence.finalize(track, endedAt: nowMilliseconds())
            hub.stop(consumer: .recording)
            clearSession()
            transition(to: .idle)
        } catch {
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: track.id))
            throw error
        }
    }

    func resetFailure() async {
        guard case .failed = state else { return }
        await ticker.stop()
        hub.stop(consumer: .recording)
        clearSession()
        transition(to: .idle)
    }

    func delete(_ track: Track) throws {
        guard activeTrackID != track.id else {
            throw RecordingError.activeTrackCannotBeDeleted
        }
        try persistence.delete(track)
    }

    func isActive(_ track: Track) -> Bool {
        activeTrackID == track.id
    }

    private func acceptTick(_ timeMs: Int64) -> Bool {
        guard case .recording = state,
              let track = activeTrack,
              track.endedAt == nil else {
            return false
        }
        if let lastAcceptedTickMs, timeMs <= lastAcceptedTickMs {
            return true
        }

        pending.append(assembler.assemble(timeMs: timeMs, state: hub.state))
        lastAcceptedTickMs = timeMs
        currentSampleCount += 1

        guard pending.count >= 5 else { return true }
        do {
            try flushPending(to: track)
            return true
        } catch {
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: track.id))
            return false
        }
    }

    private func flushPending(to track: Track) throws {
        guard !pending.isEmpty else { return }
        let batch = pending
        try persistence.append(batch, to: track)
        pending.removeAll(keepingCapacity: true)
    }

    private func clearSession() {
        activeTrack = nil
        currentSampleCount = 0
        pending.removeAll(keepingCapacity: false)
        lastAcceptedTickMs = nil
    }

    private func transition(to newState: RecordingState) {
        state = newState
        transitionHistory.append(newState.phase)
    }
}
