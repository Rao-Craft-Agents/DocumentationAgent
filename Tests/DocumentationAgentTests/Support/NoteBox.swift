import Foundation

/// The notes a host heard, kept across the threads a run says them from.
final class NoteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String] = []

    var lines: [String] { lock.withLock { kept } }

    func append(_ line: String) { lock.withLock { kept.append(line) } }
}
