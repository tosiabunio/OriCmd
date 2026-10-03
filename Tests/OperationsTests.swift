import Foundation
import Testing

@Suite("Operations history and queue")
@MainActor
struct OperationsTests {
    @Test func resultsDistinguishErrorsSkipsAndCancellation() {
        let store = OperationsStore()
        let skipped = store.start(title: "Copy", source: "s", target: "t", cancel: {})
        var state = TransferProgress.State()
        state.skippedItems = 2
        store.finish(skipped, progress: state, completedItems: 3)
        #expect(store.entries.first?.status == .skipped)
        #expect(store.entries.first?.completedItems == 3)
        let failed = store.start(title: "Copy", source: "s", target: "t", cancel: {})
        store.finish(failed, progress: TransferProgress.State(), error: TransferError(message: "disk full"))
        #expect(store.entries.first?.status == .failed)
        #expect(store.entries.first?.error == "disk full")
        let cancelled = store.start(title: "Move", source: "s", target: "t", cancel: {})
        state.isCancelled = true
        store.finish(cancelled, progress: state, error: CancellationError())
        #expect(store.entries.first?.status == .cancelled)
        #expect(store.entries.first?.error == nil)
        #expect(store.entries.allSatisfy { $0.cancel == nil })
    }

    @Test func clearingAndLimitingHistoryPreservesRunningJobs() {
        let store = OperationsStore()
        var cancelled = false
        let active = store.start(title: "Active", source: "s", target: "t") { cancelled = true }
        for n in 0..<110 {
            let id = store.start(title: String(n), source: "s", target: "t", cancel: {})
            store.finish(id, progress: TransferProgress.State())
        }
        #expect(store.entries.count == 101)
        #expect(store.runningCount == 1)
        store.clearFinished()
        #expect(store.entries.map(\.id) == [active])
        store.cancel(active)
        #expect(cancelled)
        store.finish(active, progress: TransferProgress.State())
        store.update(active, progress: TransferProgress.State())
        #expect(store.entries.first?.status == .completed)
    }

    @Test func cancellingAWaitingJobNeverExecutesItAndQueueContinues() async {
        let store = OperationsStore()
        let queue = TransferQueue(store: store)
        var gate: CheckedContinuation<Void, Never>?
        var cancelledJobRan = false
        var lastRan = false
        queue.add(title: "First", source: "s", target: "t") {
            await withCheckedContinuation { gate = $0 }
        }
        while gate == nil { await Task.yield() }
        queue.add(title: "Cancelled", source: "s", target: "t") { cancelledJobRan = true }
        let pending = queue.pending[0].id
        queue.cancel(pending)
        queue.add(title: "Last", source: "s", target: "t") { lastRan = true }
        #expect(queue.waitingCount == 1)
        #expect(store.entries.first?.status == .cancelled)
        gate?.resume()
        for _ in 0..<1000 where !lastRan { await Task.yield() }
        #expect(lastRan)
        #expect(!cancelledJobRan)
        #expect(queue.waitingCount == 0)
    }
}
