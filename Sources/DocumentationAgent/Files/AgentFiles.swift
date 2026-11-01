//  WHAT: Where a call's files go and how they land: paths read from the host's folder, every file staged in a
//        folder of its own first, Swift checked there, then moved into the project together.
//  PIN:  WHOLE OR NOTHING. A call that fails a check writes nothing into the project, so a turn never builds half of
//        what an agent meant; the staging folder goes with the process's temporary files.
//  PIN:  NEVER PRINT. Stdout is the wire's; a check's output is read from its own pipe.
//  PIN:  THE HOST'S PATHS, AS THE HOST WROTE THEM. `standardizedFileURL` turns /private/tmp into /tmp, and an answer
//        naming /tmp/x no longer lies inside the /private/tmp/x the host gave; only `..` is ever resolved.

import Foundation

struct AgentFiles: Sendable {
    /// The folder the call works in: the host's, else the process's.
    let root: URL

    init(directory: String?) {
        let base = directory.map { ($0 as NSString).expandingTildeInPath } ?? FileManager.default.currentDirectoryPath
        root = URL(fileURLWithPath: Self.resolvingParents(base), isDirectory: true)
    }

    /// `path` read from the root when it is relative, and as it is when absolute.
    func resolve(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: Self.resolvingParents(expanded)) }
        return URL(fileURLWithPath: Self.resolvingParents(root.path + "/" + expanded))
    }

    /// `url` relative to the root when it is inside it; absolute otherwise.
    func relative(_ url: URL) -> String {
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for path in [url.path, url.standardizedFileURL.path] where path.hasPrefix(base) { return String(path.dropFirst(base.count)) }
        let standardBase = root.standardizedFileURL.path + "/"
        let standard = url.standardizedFileURL.path
        return standard.hasPrefix(standardBase) ? String(standard.dropFirst(standardBase.count)) : url.path
    }

    /// An absolute path with `.` and `..` resolved and empty components dropped, and nothing else changed.
    static func resolvingParents(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Writes `files` (absolute URL → text): staged, every `.swift` among them parsed, then moved into place.
    /// Answers the absolute paths written, in the order given.
    func write(_ files: [(url: URL, text: String)]) throws -> [String] {
        let manager = FileManager.default
        let stage = manager.temporaryDirectory.appendingPathComponent("agent-stage-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? manager.removeItem(at: stage) }
        var staged: [(from: URL, to: URL)] = []
        for (index, file) in files.enumerated() {
            let name = "\(index)-" + file.url.lastPathComponent
            let place = stage.appendingPathComponent(name)
            try manager.createDirectory(at: stage, withIntermediateDirectories: true)
            try Data(file.text.utf8).write(to: place)
            staged.append((place, file.url))
        }
        let swift = staged.filter { $0.to.pathExtension == "swift" }
        if !swift.isEmpty, let failure = try SwiftParse.check(swift.map(\.from)) {
            // Name the file as the project will know it, not the staging copy.
            let named = swift.reduce(failure) { text, pair in text.replacingOccurrences(of: pair.from.path, with: relative(pair.to)) }
            throw AgentFilesError.unparsed(named)
        }
        var written: [String] = []
        for pair in staged {
            do {
                try manager.createDirectory(at: pair.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if manager.fileExists(atPath: pair.to.path) { try manager.removeItem(at: pair.to) }
                try manager.moveItem(at: pair.from, to: pair.to)
            } catch {
                throw AgentFilesError.unwritable(pair.to.path)
            }
            written.append(pair.to.path)
        }
        return written
    }
}

enum AgentFilesError: Error, Equatable, CustomStringConvertible {
    /// Swift that does not parse: the compiler's lines, naming each file as the project knows it.
    case unparsed(String)
    case unwritable(String)

    var description: String {
        switch self {
        case .unparsed(let lines): return "the Swift written does not parse, so nothing was written:\n\(lines)"
        case .unwritable(let path): return "could not write \(path)"
        }
    }
}
