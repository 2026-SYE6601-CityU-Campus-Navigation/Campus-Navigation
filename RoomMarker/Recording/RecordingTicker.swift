import Foundation

@MainActor
protocol RecordingTicking: AnyObject {
    typealias Handler = @MainActor @Sendable (Int64) async -> Bool

    func start(handler: @escaping Handler)
    func stop() async
}

@MainActor
final class ForegroundRecordingTicker: RecordingTicking {
    private let interval: Duration
    private let nowMilliseconds: @MainActor @Sendable () -> Int64
    private var task: Task<Void, Never>?

    init(
        interval: Duration = .seconds(1),
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.interval = interval
        self.nowMilliseconds = nowMilliseconds
    }

    func start(handler: @escaping Handler) {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                let shouldContinue = await handler(nowMilliseconds())
                guard shouldContinue else { break }
            }
        }
    }

    func stop() async {
        guard let task else { return }
        task.cancel()
        _ = await task.result
        self.task = nil
    }
}
