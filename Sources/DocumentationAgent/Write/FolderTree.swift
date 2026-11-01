//  WHAT: The project's folder tree as a README shows it: the folders that hold code, two levels deep, a line each
//        from the code: what the folder's root type, its service or its README says it is, else what its files declare.

import Foundation

struct FolderTree {
    let model: ProjectModel
    var depth = 2
    var perFolder = 12

    /// How many code files `path` holds, at any depth.
    func codeFiles(_ path: String) -> Int {
        let prefix = path == "." ? "" : path + "/"
        return model.scan.files.filter { $0.path.hasPrefix(prefix) }.count
    }

    /// The line a folder gets: what the code says it is, else what it declares, else what it holds.
    func line(_ path: String) -> String {
        guard let f = model.folders[path] else { return "" }
        if let about = f.about, about.from != "group" { return ProseDigest.clip(SwiftSource.firstSentence(about.text), 96) }
        if let holds = f.holds { return ProseDigest.clip(holds, 96) }
        let prefix = path + "/"
        let direct = model.swift.filter { ($0.path as NSString).deletingLastPathComponent == path }
        let declared = direct.flatMap { $0.scopes.filter { $0.parent < 0 && $0.isType }.map(\.name) }
        var unique: [String] = []
        for name in declared where !unique.contains(name) { unique.append(name) }
        if !unique.isEmpty { return ProseDigest.clip("declares " + ProjectModel.list(unique.prefix(4).map { "`\($0)`" }) + (unique.count > 4 ? " and \(unique.count - 4) more" : ""), 96) }
        if f.kind == "group", let about = f.about { return about.text }
        let files = model.scan.files.filter { $0.path.hasPrefix(prefix) }
        let languages = Dictionary(grouping: files, by: \.language).sorted { $0.value.count > $1.value.count }.map { "\($0.value.count) \($0.key)" }
        return files.isEmpty ? "" : ProjectModel.list(languages.prefix(2).map { $0 }) + " file" + (files.count == 1 ? "" : "s")
    }

    /// The tree, as lines for a fenced block: the root's name, then its folders with their lines aligned.
    func lines() -> [String] {
        var rows: [(String, String)] = [(model.title + "/", "")]
        func visit(_ path: String, _ prefix: String, _ level: Int) {
            guard let f = model.folders[path] else { return }
            var kids = f.folders.map { path == "." ? $0 : path + "/" + $0 }.filter { codeFiles($0) > 0 }
            var more = 0
            if kids.count > perFolder {
                let kept = Set(kids.sorted { codeFiles($0) > codeFiles($1) }.prefix(perFolder))
                more = kids.count - perFolder
                kids = kids.filter { kept.contains($0) }
            }
            for (i, kid) in kids.enumerated() {
                let last = i == kids.count - 1 && more == 0
                let name = (kid as NSString).lastPathComponent + "/"
                rows.append((prefix + (last ? "└── " : "├── ") + name, line(kid)))
                // A folder that only wraps one other (`Sources/` around a package's one target) spends no level.
                let wraps = (model.folders[kid]?.files1 ?? 0) == 0 && (model.folders[kid]?.folders.filter { codeFiles(kid + "/" + $0) > 0 }.count ?? 0) == 1
                if level < depth || (wraps && level < depth + 1) { visit(kid, prefix + (last ? "    " : "│   "), wraps ? level : level + 1) }
            }
            if more > 0 { rows.append((prefix + "└── …", "and \(more) more folder\(more == 1 ? "" : "s")")) }
        }
        visit(".", "", 1)
        let width = min(40, rows.map { $0.0.count }.max() ?? 0)
        return rows.map { left, right in
            right.isEmpty ? left : left.padding(toLength: max(width, left.count), withPad: " ", startingAt: 0) + "  " + right.replacingOccurrences(of: "`", with: "")
        }
    }
}
