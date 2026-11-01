//  WHAT: One file the documentation reads: its path from the project's root, its language, and its text.

import Foundation

struct ProjectFile: Sendable {
    /// The languages read as code, by extension: every one gets folder and file pages and search; Swift alone is
    /// walked for declarations, calls and flows.
    static let languages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++", "h": "C header", "c": "C", "cc": "C++", "cpp": "C++", "hpp": "C++",
        "ts": "TypeScript", "tsx": "TypeScript", "js": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript",
        "py": "Python", "go": "Go", "rs": "Rust", "kt": "Kotlin", "kts": "Kotlin", "java": "Java", "rb": "Ruby", "cs": "C#",
        "php": "PHP", "scala": "Scala", "sh": "Shell", "zsh": "Shell", "bash": "Shell", "lua": "Lua", "dart": "Dart",
        "ex": "Elixir", "exs": "Elixir", "sql": "SQL", "graphql": "GraphQL", "proto": "Protocol Buffers", "metal": "Metal",
        "vue": "Vue", "svelte": "Svelte", "css": "CSS", "scss": "SCSS", "html": "HTML",
    ]

    /// The path from the project's root, with `/` between folders.
    let path: String
    let language: String
    let text: String
    let lines: Int
    let bytes: Int

    init(path: String, language: String, text: String) {
        self.path = path
        self.language = language
        self.text = text
        bytes = text.utf8.count
        var count = 0
        for byte in text.utf8 where byte == 10 { count += 1 }
        lines = count + (text.isEmpty || text.hasSuffix("\n") ? 0 : 1)
    }

    var name: String { (path as NSString).lastPathComponent }
    var folder: String { let f = (path as NSString).deletingLastPathComponent; return f.isEmpty ? "." : f }
    var isSwift: Bool { language == "Swift" }
    var isMarkdown: Bool { language == "Markdown" }
    /// The folder at the project's top level it sits in, or `.` for a file at the root.
    var topFolder: String { path.contains("/") ? String(path.split(separator: "/")[0]) : "." }
}
