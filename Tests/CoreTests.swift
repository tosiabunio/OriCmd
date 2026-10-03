import Foundation
import Testing

@Suite("File masks, filters and names")
struct FileNameTests {
    @Test func masksIgnoreCaseAndAcceptMultiplePatterns() {
        #expect(FileMask.matches("README.MD", "*.txt;*.md"))
        #expect(FileMask.matches("без расширения", "*.*"))
        #expect(!FileMask.matches("photo.png", "*.txt *.md"))
    }

    @Test func folderIncludesStillRespectExclusions() {
        let filter = CopyFilter("src/ | *.bak .git/")
        #expect(filter.includesFolder("src"))
        #expect(filter.includesFile("main.swift", insideIncludedFolder: true))
        #expect(!filter.includesFile("old.bak", insideIncludedFolder: true))
        #expect(!filter.includesFile("main.swift", insideIncludedFolder: false))
        #expect(filter.excludesFolder(".git"))
    }

    @Test func renameMasksPreserveHiddenNamesAndReplaceExtensions() {
        #expect(RenameMask("new_*.*")?.apply(to: "report.txt") == "new_report.txt")
        #expect(RenameMask("*.bak")?.apply(to: ".profile") == ".profile.bak")
        #expect(RenameMask("*.*") == nil)
    }
}

@Suite("Text comparison")
struct TextComparisonTests {
    @Test func insertedLinesStayAligned() {
        let rows = TextDiff.rows(TextDiff.lines(of: "a\nb\nc\n"), TextDiff.lines(of: "a\nnew\nb\nc\n"),
                                 ignoringWhitespace: false)
        #expect(rows.count == 4)
        #expect(rows[1].left == nil && rows[1].right == 1 && rows[1].kind == .rightOnly)
        #expect(rows[2].left == 1 && rows[2].right == 2 && rows[2].kind == .same)
    }

    @Test func whitespaceOptionPreservesActualChanges() {
        let rows = TextDiff.rows(["a  b", "different"], ["a\tb", "other"], ignoringWhitespace: true)
        #expect(rows[0].kind == .same)
        #expect(rows[1].kind == .changed)
        #expect(TextDiff.blockStarts(rows) == [1])
    }

    @Test func changedRangesUseUTF16Offsets() {
        let (left, right) = TextDiff.changedRanges("😀abc", "😀axc")
        #expect(left == NSRange(location: 3, length: 1))
        #expect(right == NSRange(location: 3, length: 1))
    }
}

@Suite("Local file transfer")
struct TransferTests {
    private func withFolders(_ body: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OriCmd-core-tests-\(UUID())")
        let source = root.appending(path: "source"), target = root.appending(path: "target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(source, target)
    }

    @Test func copyVerifiesContentsAndPreservesSource() async throws {
        try await withFolders { source, target in
            let file = source.appending(path: "file.txt")
            let data = Data(repeating: 0x41, count: 8192)
            try data.write(to: file)
            var options = TransferOptions()
            options.verify = true
            let job = TransferJob(kind: .copy, sources: [file], destination: target, newName: nil, options: options)
            let done = try await TransferEngine(job: job, progress: TransferProgress(), resolveConflict: { _, _ in .cancel }).run()
            #expect(done == [file])
            #expect(try Data(contentsOf: target.appending(path: "file.txt")) == data)
            #expect(try Data(contentsOf: file) == data)
        }
    }

    @Test func skippedMovePreservesBothFiles() async throws {
        try await withFolders { source, target in
            let file = source.appending(path: "file.txt"), existing = target.appending(path: "file.txt")
            try Data("source".utf8).write(to: file)
            try Data("target".utf8).write(to: existing)
            let job = TransferJob(kind: .move, sources: [file], destination: target, newName: nil)
            let done = try await TransferEngine(job: job, progress: TransferProgress(), resolveConflict: { _, _ in .skip }).run()
            #expect(done.isEmpty)
            #expect(try Data(contentsOf: file) == Data("source".utf8))
            #expect(try Data(contentsOf: existing) == Data("target".utf8))
        }
    }

    @Test func cancelledCopyPreservesExistingTarget() async throws {
        try await withFolders { source, target in
            let file = source.appending(path: "file.txt"), existing = target.appending(path: "file.txt")
            try Data("source".utf8).write(to: file)
            try Data("target".utf8).write(to: existing)
            let progress = TransferProgress()
            progress.cancel()
            let job = TransferJob(kind: .copy, sources: [file], destination: target, newName: nil)
            await #expect(throws: CancellationError.self) {
                try await TransferEngine(job: job, progress: progress, resolveConflict: { _, _ in .overwrite }).run()
            }
            #expect(try Data(contentsOf: existing) == Data("target".utf8))
        }
    }

    @Test func selfCopyThroughSymlinkIsRefused() async throws {
        try await withFolders { source, target in
            let file = source.appending(path: "file.txt"), link = target.appending(path: "link")
            try Data("keep".utf8).write(to: file)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            let job = TransferJob(kind: .copy, sources: [file], destination: link, newName: nil)
            await #expect(throws: TransferError.self) {
                try await TransferEngine(job: job, progress: TransferProgress(), resolveConflict: { _, _ in .overwrite }).run()
            }
            #expect(try Data(contentsOf: file) == Data("keep".utf8))
        }
    }
}
