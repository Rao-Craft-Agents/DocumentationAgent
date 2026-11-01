import Foundation

/// A pipe read to its end on a thread of its own.
final class LogReader: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ handle: FileHandle) {
        Thread.detachNewThread { [self] in
            data = handle.readDataToEndOfFile()
            done.signal()
        }
    }

    func text() -> String {
        done.wait()
        return String(decoding: data, as: UTF8.self)
    }
}
