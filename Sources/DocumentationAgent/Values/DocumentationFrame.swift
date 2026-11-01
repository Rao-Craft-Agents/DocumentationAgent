import Foundation

/// What a run says as it goes.
public enum DocumentationFrame: Sendable {
    /// The project was read: how many files, and how many lines of them.
    case read(files: Int, lines: Int)
    /// The Swift was walked: its declarations and the calls matched between them.
    case parsed(declarations: Int, calls: Int)
    /// The files are written.
    case written(DocumentationResult)

    public var result: DocumentationResult? {
        if case .written(let result) = self { return result }
        return nil
    }
}
