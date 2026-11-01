//  WHAT: What the model reads before it writes prose: a digest of the code, made from the code, capped, with every
//        file it names listed, so an answer can be held to citing only files the model was shown.
//  PIN:  GROUNDED IN THE DIGEST. A claim the model makes must cite a file the digest names (`citable`); a file it was
//        not shown cannot ground a sentence, even when the project has it.

import Foundation

struct ProseDigest: Sendable {
    var text: String
    var citable: Set<String>

    /// The whole project: its manifests, its folders with what each is, its packages, services and components, and the
    /// files that say what they are, ranked so the ones that hold the project together come first.
    static func project(_ model: ProjectModel, leaving: Set<String>, limit: Int = 11_000) -> ProseDigest {
        var lines: [String] = []
        var citable: Set<String> = []
        func cite(_ path: String) -> String { citable.insert(path); return path }
        lines.append("Project: \(model.title)")
        for x in model.manifest.xcode {
            let targets = x.targets.map { "\($0.name) (\($0.kind))" }.joined(separator: ", ")
            let os = x.deployment.keys.sorted().map { "\($0) \(x.deployment[$0]!)" }.joined(separator: ", ")
            lines.append("Xcode project \(x.path): targets \(targets)" + (os.isEmpty ? "" : "; deploys to \(os)"))
        }
        for p in model.manifest.packages {
            let products = p.products.map(\.name).joined(separator: ", ")
            let deps = p.dependencies.map(\.name).joined(separator: ", ")
            lines.append("Swift package \(p.name) (\(cite(p.folder == "." ? "Package.swift" : p.folder + "/Package.swift")))" + (products.isEmpty ? "" : ": products \(products)")
                         + (deps.isEmpty ? "" : "; depends on \(deps)") + (p.about.map { ". It says: " + $0 } ?? ""))
        }
        if let node = model.manifest.node {
            lines.append("package.json: \(node.name ?? model.title)" + (node.description.map { ", \"\($0)\"" } ?? "") + "; scripts " + node.scripts.map(\.name).joined(separator: ", "))
            citable.insert("package.json")
        }
        let readmes = model.scan.docs.filter { $0.name.lowercased().hasPrefix("readme") && !leaving.contains($0.path) }
        for doc in readmes.prefix(12) {
            if let first = Markdown.firstParagraph(doc.text, limit: 280) { lines.append("\(cite(doc.path)) says: \(first)") }
        }
        lines.append("")
        lines.append("Folders at the top, with what their code says they are:")
        for name in model.folders["."]?.folders ?? [] {
            guard let f = model.folders[name] else { continue }
            var line = "- \(name)/ (\(f.filesAll) files, \(f.linesAll) lines)"
            if let about = f.about { line += ": " + clip(about.text, 200); if let source = about.source { line += " [\(cite(source))]" } }
            lines.append(line)
        }
        if !model.services.isEmpty {
            lines.append("")
            lines.append("Granite services, lowest rank first (each: its file, its events, the services it reaches):")
            for s in model.services {
                lines.append("- \(s.name) (\(cite(s.path))): events " + (s.events.map(\.event).joined(separator: ", ").nonEmpty ?? "none")
                             + (s.reaches.isEmpty ? "" : "; reaches " + s.reaches.joined(separator: ", ")) + (s.what.map { ". " + clip($0, 160) } ?? ""))
            }
        }
        if !model.components.isEmpty {
            lines.append("")
            lines.append("Granite components (each: its file, the services it reads, its events):")
            for c in model.components {
                lines.append("- \(c.name) (\(cite(c.path)))" + (c.relays.isEmpty ? "" : ": reads " + c.relays.joined(separator: ", "))
                             + (c.events.isEmpty ? "" : "; events " + c.events.map(\.event).joined(separator: ", ")))
            }
        }
        lines.append("")
        lines.append("Files that say what they are:")
        var body = lines.joined(separator: "\n")
        for (path, summary) in ranked(model) where !leaving.contains(path) {
            let line = "\n- \(path): \(clip(summary, 220))"
            if body.count + line.count > limit { break }
            body += line
            citable.insert(path)
        }
        if let graph = model.graph, body.count < limit - 400 {
            let types = graph.scopes.indices.filter { graph.scopes[$0].isType && graph.scopes[$0].parent < 0 && !graph.scopes[$0].mods.contains("private") }
            var said = "\n\nTypes the code declares (file):"
            for g in types {
                let path = graph.files[graph.fileOf[g]].path
                let line = "\n- \(graph.scopes[g].name) (\(path))"
                if body.count + said.count + line.count > limit { break }
                said += line
                citable.insert(path)
            }
            body += said
        }
        return ProseDigest(text: body, citable: citable)
    }

    /// One folder: what it is, its folders, the services and components in it, and its files with what each says or
    /// declares.
    static func folder(_ model: ProjectModel, path: String, limit: Int = 6_000) -> ProseDigest {
        var citable: Set<String> = []
        guard let f = model.folders[path] else { return ProseDigest(text: "", citable: []) }
        var lines = ["Folder \(path)/ of \(model.title): \(f.filesAll) files, \(f.linesAll) lines."]
        if let about = f.about {
            lines.append("What its code says it is: \(clip(about.text, 300))" + (about.source.map { " [\($0)]" } ?? ""))
            if let source = about.source { citable.insert(source) }
        }
        for name in f.folders {
            let child = path + "/" + name
            guard let c = model.folders[child] else { continue }
            lines.append("- \(child)/ (\(c.filesAll) files)" + (c.about.map { ": " + clip($0.text, 160) } ?? ""))
            if let source = c.about?.source { citable.insert(source) }
        }
        for s in (model.services + model.components) where s.folder == path || s.folder.hasPrefix(path + "/") {
            lines.append("- \(s.isComponent ? "Component" : "Service") \(s.name) (\(s.path)): events " + (s.events.map(\.event).joined(separator: ", ").nonEmpty ?? "none")
                         + (s.relays.isEmpty ? "" : "; holds " + s.relays.joined(separator: ", ")))
            citable.insert(s.path)
        }
        var body = lines.joined(separator: "\n") + "\n\nIts files:"
        for file in model.scan.files where file.path.hasPrefix(path + "/") {
            var said = file.isSwift ? (model.swiftSource(file.path)?.summary ?? "") : OtherSource.summary(file)
            if said.isEmpty, let source = model.swiftSource(file.path) {
                let declared = source.scopes.filter { $0.parent < 0 }.prefix(4).map { "\($0.keyword) \($0.name)" }
                said = declared.isEmpty ? "" : "declares " + declared.joined(separator: ", ")
            }
            guard !said.isEmpty else { continue }
            let line = "\n- \(file.path): \(clip(said, 200))"
            if body.count + line.count > limit { break }
            body += line
            citable.insert(file.path)
        }
        return ProseDigest(text: body, citable: citable)
    }

    /// The files that say what they are, the ones that hold the project together first: a service's or component's
    /// root, a folder's root type, then the shallow before the deep.
    static func ranked(_ model: ProjectModel) -> [(String, String)] {
        let roots = Set((model.services + model.components).map(\.path) + model.folders.values.compactMap { $0.rootType?.path })
        let said: [(path: String, summary: String)] = model.scan.files.compactMap { file in
            let summary = file.isSwift ? (model.swiftSource(file.path)?.summary ?? "") : OtherSource.summary(file)
            return summary.isEmpty ? nil : (file.path, summary)
        }
        return said.sorted { a, b in
            let ka = (roots.contains(a.path) ? 0 : 1, a.path.split(separator: "/").count, a.path)
            let kb = (roots.contains(b.path) ? 0 : 1, b.path.split(separator: "/").count, b.path)
            return ka < kb
        }.map { ($0.path, $0.summary) }
    }

    static func clip(_ text: String, _ count: Int) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > count ? String(flat.prefix(count - 1)) + "…" : flat
    }
}
