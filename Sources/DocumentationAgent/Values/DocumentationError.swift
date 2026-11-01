import Foundation

/// What a call can say instead of writing.
public enum DocumentationError: Error, Equatable, CustomStringConvertible {
    /// What the call asked for that cannot be done, one sentence a problem, every problem at once.
    case refused([String])
    /// The folders read hold no file to document.
    case nothing(String)

    public var description: String {
        switch self {
        case .refused(let reasons):
            let head = reasons.count == 1 ? "1 problem, so nothing was written" : "\(reasons.count) problems, so nothing was written"
            return head + ":\n" + reasons.map { "- \($0)" }.joined(separator: "\n")
        case .nothing(let folder):
            return "\(folder) holds no source file to document: name the folders with `sources`"
        }
    }
}
