import Foundation

/// Session history and live progress. Finished entries release their cancellation closures.
@MainActor
final class OperationsStore {
    static let shared = OperationsStore()
    static let didChange = Notification.Name("OperationsDidChange")

    enum Status { case running, completed, skipped, failed, cancelled }
    struct Entry {
        let id: UUID
        let title: String
        let source: String
        let target: String
        var status: Status = .running
        var progress = TransferProgress.State()
        var completedItems = 0
        var error: String?
        var cancel: (() -> Void)?
    }
    private(set) var entries: [Entry] = []
    var runningCount: Int { entries.count { $0.status == .running } }

    @discardableResult
    func start(title: String, source: String, target: String, cancel: @escaping () -> Void) -> UUID {
        let id = UUID()
        entries.insert(Entry(id: id, title: title, source: source, target: target, cancel: cancel), at: 0)
        changed()
        return id
    }

    func update(_ id: UUID, progress: TransferProgress.State) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.status == .running }) else { return }
        entries[index].progress = progress
        changed()
    }

    func finish(_ id: UUID, progress: TransferProgress.State, completedItems: Int = 0, error: Error? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].progress = progress
        entries[index].completedItems = completedItems
        let cancelled = progress.isCancelled || error is CancellationError
        entries[index].error = cancelled ? nil : error?.localizedDescription
        entries[index].status = cancelled ? .cancelled
            : error != nil ? .failed : progress.skippedItems > 0 ? .skipped : .completed
        entries[index].cancel = nil
        // Keep all running jobs and the most recent 100 finished results.
        var finished = 0
        entries.removeAll { entry in
            guard entry.status != .running else { return false }
            finished += 1
            return finished > 100
        }
        changed()
    }

    func cancel(_ id: UUID) { entries.first { $0.id == id && $0.status == .running }?.cancel?() }
    func clearFinished() { entries.removeAll { $0.status != .running }; changed() }
    func recordQueuedCancellation(title: String, source: String, target: String) {
        let id = start(title: title, source: source, target: target, cancel: {})
        var state = TransferProgress.State()
        state.isCancelled = true
        finish(id, progress: state)
    }
    func changed() { NotificationCenter.default.post(name: Self.didChange, object: self) }
}
