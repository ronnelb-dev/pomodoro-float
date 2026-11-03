import Foundation

final class WindowFrameSaveScheduler<Value> {
    typealias ScheduleAfter = (TimeInterval, @escaping () -> Void) -> (() -> Void)

    private let debounceInterval: TimeInterval
    private let scheduleAfter: ScheduleAfter
    private let save: (Value) -> Void
    private var pendingValue: Value?
    private var cancelScheduledWork: (() -> Void)?
    private var scheduleGeneration = 0

    init(debounceInterval: TimeInterval = 0.35,
         scheduleAfter: @escaping ScheduleAfter = { delay, action in
             let work = DispatchWorkItem(block: action)
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
             return { work.cancel() }
         },
         save: @escaping (Value) -> Void) {
        self.debounceInterval = debounceInterval
        self.scheduleAfter = scheduleAfter
        self.save = save
    }

    func schedule(_ value: Value) {
        cancelScheduledWork?()
        pendingValue = value
        scheduleGeneration += 1
        let generation = scheduleGeneration
        cancelScheduledWork = scheduleAfter(debounceInterval) { [weak self] in
            guard let self, self.scheduleGeneration == generation else { return }
            self.flush()
        }
    }

    func flush() {
        cancelScheduledWork?()
        cancelScheduledWork = nil
        scheduleGeneration += 1
        guard let value = pendingValue else { return }
        pendingValue = nil
        save(value)
    }

    deinit {
        cancelScheduledWork?()
    }
}
