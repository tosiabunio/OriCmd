import Foundation

/// "F2 Queue": pending operations can be inspected and cancelled before they run.
@MainActor
final class TransferQueue {
    static let shared = TransferQueue()
    struct Pending {
        let id: UUID
        let title: String
        let source: String
        let target: String
        let run: () async -> Void
    }
    private(set) var pending: [Pending] = []
    private var isRunning = false
    private let store: OperationsStore

    init(store: OperationsStore = .shared) { self.store = store }
    var waitingCount: Int { pending.count }

    func add(title: String, source: String, target: String, _ job: @escaping () async -> Void) {
        pending.append(Pending(id: UUID(), title: title, source: source, target: target, run: job))
        store.changed()
        guard !isRunning else { return }
        isRunning = true
        Task {
            while !pending.isEmpty {
                let next = pending.removeFirst()
                store.changed()
                await next.run()
            }
            isRunning = false
            store.changed()
        }
    }

    func cancel(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let job = pending.remove(at: index)
        store.recordQueuedCancellation(title: job.title, source: job.source, target: job.target)
    }
}
