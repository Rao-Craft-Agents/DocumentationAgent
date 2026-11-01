//  WHAT: A project's Markdown docs, from its code: `Architecture.md` (its modules in dependency order, its targets, its
//        folders, its services by rank and its components), one page per folder at its top led by what its code says
//        of itself (with the model's overview when there is one), `Glossary.md` (its types, one line each) and
//        `Building.md` (what it needs, and how to build and test it).

import Foundation

struct MarkdownWriter {
    let model: ProjectModel
    let build: BuildFacts
    /// The folder the docs go in, from the project's root.
    let folder: String
    /// The model's overview of each folder, by path.
    var overviews: [String: ProseAnswer] = [:]

    static let reserved: Set<String> = ["Architecture", "Glossary", "Building"]

    /// The folders at the top that hold code: each gets a page.
    var topFolders: [String] {
        (model.folders["."]?.folders ?? []).filter { name in model.scan.files.contains { $0.path.hasPrefix(name + "/") } }
    }

    /// The page a top-level folder is written to.
    func pageName(_ folder: String) -> String {
        let safe = folder.replacingOccurrences(of: "/", with: "-")
        return (Self.reserved.contains(safe) ? "Folder-" + safe : safe) + ".md"
    }

    func files() -> [(name: String, text: String)] {
        [("Architecture.md", architecture())] + topFolders.map { (pageName($0), page($0)) } + [("Glossary.md", glossary()), ("Building.md", building())]
    }

    private func link(_ path: String) -> String { Markdown.link(path, from: folder) }
    private func fileLink(_ path: String, line: Int? = nil) -> String {
        "[\((path as NSString).lastPathComponent)\(line.map { ":\($0)" } ?? "")](\(link(path))\(line.map { "#L\($0)" } ?? ""))"
    }

    private func lede(_ path: String) -> [String] {
        guard let about = model.folders[path]?.about else {
            guard path != "." else { return [] }
            let missing = "no root type says what this folder is: there is no `\((path as NSString).lastPathComponent).swift` with a doc comment or a WHAT, and no README"
            if let holds = model.folders[path]?.holds { return ["It holds \(holds). *(Read off its code: \(missing).)*", ""] }
            return [missing.prefix(1).uppercased() + missing.dropFirst() + ".", ""]
        }
        let source = about.source.map { " *(From \(fileLink($0)).)*" } ?? ""
        return [Markdown.inline(about.text) + source, ""]
    }

    private func overview(_ path: String, from page: String) -> [String] {
        guard let answer = overviews[path], !answer.sentences.isEmpty else { return [] }
        let text = answer.sentences.map { claim -> String in
            let body = Markdown.inline(claim.text.trimmingCharacters(in: .whitespaces))
            let links = claim.files.map { "[\(($0 as NSString).lastPathComponent)](\(link($0)))" }.joined(separator: ", ")
            return (body.hasSuffix(".") ? String(body.dropLast()) : body) + " (" + links + ")."
        }.joined(separator: " ")
        return [text, ""]
    }

    // MARK: - Architecture.md

    func architecture() -> String {
        var out = ["# \(model.title): architecture", ""]
        out += lede(".")
        let swift = model.swift.count, others = model.scan.files.count - swift
        let lines = model.scan.files.reduce(0) { $0 + $1.lines }
        var counts = "\(Markdown.count(model.scan.files.count)) files of code, \(Markdown.count(lines)) lines"
        if swift > 0 {
            counts += "; \(Markdown.count(swift)) Swift file\(swift == 1 ? "" : "s") walked into \(Markdown.count(model.graph?.scopes.count ?? 0)) declarations and "
                + "\(Markdown.count(model.graph?.edges.count ?? 0)) matched calls"
        }
        if others > 0 { counts += "; \(Markdown.count(others)) in other languages" }
        out += [counts + ".", ""]
        let order = ModuleOrder(model)
        if order.modules.count > 1 {
            out += ["## Modules, in dependency order", "", "Read off the manifests and every Swift file's imports: a module sits one layer above the highest module of the project it imports.", "",
                    "| Layer | Module | What it is | Files | Imports |", "|---|---|---|---|---|"]
            for m in order.modules {
                let place = m.folder == "." ? m.kind : "[\(m.folder)](\(link(m.folder))), \(m.kind)"
                out.append("| \(m.layer) | \(m.name) | \(Markdown.cell(place)) | \(m.files) | " + Markdown.cell(m.imports.sorted().joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        for p in model.manifest.packages where !p.targets.isEmpty {
            out += ["## \(p.folder == "." ? "The package" : "Package \(p.name)")", "",
                    "From [\(p.folder == "." ? "Package.swift" : p.folder + "/Package.swift")](\(link(p.folder == "." ? "Package.swift" : p.folder + "/Package.swift")))"
                    + (p.platforms.isEmpty ? "" : ", for " + ProjectModel.list(p.platforms)) + ".", "",
                    "| Target | Kind | Layer | Depends on |", "|---|---|---|---|"]
            for t in p.targets {
                out.append("| [\(t.name)](\(link(p.sourceFolder(t)))) | \(t.kind) | \(t.isTest ? "–" : String(t.layer)) | "
                           + Markdown.cell((t.targets + t.products.map(\.name)).joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        for x in model.manifest.xcode {
            out += ["## \(x.path)", "", "| Target | What it makes | Builds for |", "|---|---|---|"]
            out += x.targets.map { "| \(Markdown.cell($0.name)) | \($0.kind) | \($0.sdk ?? "–") |" }
            out += ["", "Schemes: " + (x.schemes.map { "`\($0.name)`" + ($0.tests ? " (tests)" : "") }.joined(separator: ", ").nonEmpty ?? "none shared") + ".", ""]
        }
        let tops = topFolders
        if !tops.isEmpty {
            out += ["## Folders", "", "| Folder | What it holds | Files | Lines |", "|---|---|---|---|"]
            let tree = FolderTree(model: model)
            for name in tops {
                let f = model.folders[name]!
                out.append("| [\(name)/](\(pageName(name).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pageName(name))) | " + Markdown.cell(tree.line(name))
                           + " | \(Markdown.count(f.filesAll)) | \(Markdown.count(f.linesAll)) |")
            }
            let rootFiles = model.scan.files.filter { !$0.path.contains("/") }
            if !rootFiles.isEmpty { out += ["", "At the root: " + rootFiles.map { "[\($0.name)](\(link($0.path)))" }.joined(separator: ", ") + "."] }
            out.append("")
        }
        out += services(model.services, components: model.components, from: ".")
        if let graph = model.graph, !graph.edges.isEmpty {
            let tiers = (0..<3).map { t in graph.edges.filter { $0.tier == t && $0.via == nil }.count }
            var flows: [String: Int] = [:]
            for e in graph.edges { if let via = e.via { flows[via, default: 0] += 1 } }
            out += ["## Calls", "", "Read by a lexer and a brace walk, not a compiler: each call is matched to the declarations it can reach by name and argument labels. "
                    + "\(Markdown.count(tiers[0])) are exact (one declaration fits and its type is named), \(Markdown.count(tiers[1])) likely (the name is unique), "
                    + "\(Markdown.count(tiers[2])) ambiguous (two to eight fit)"
                    + (flows.isEmpty ? "." : "; \(Markdown.count(flows.values.reduce(0, +))) are Granite flows or calls through a protocol: "
                       + flows.keys.sorted().map { "\(Markdown.count(flows[$0]!)) \($0)" }.joined(separator: ", ") + "."), ""]
        }
        if !model.cycles.isEmpty { out += ["The services reach each other in a circle: " + model.cycles.joined(separator: "; ") + ". The ranks are read with that edge cut.", ""] }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private func services(_ services: [ServiceFacts], components: [ServiceFacts], from path: String) -> [String] {
        var out: [String] = []
        if !services.isEmpty {
            out += ["## Services", "", "Each is a Granite service: its center declares its events and a reducer answers each; its rank is one above the highest service its code relays to or sends an event to.", ""]
            for s in services {
                out += ["### \(s.name)", "", "Rank \(s.rank), in \(fileLink(s.path, line: s.line))" + (s.reaches.isEmpty ? "." : "; it reaches " + ProjectModel.list(s.reaches.map { "`\($0)`" }) + ".")
                        + (s.relays.isEmpty ? "" : " It holds a relay to " + ProjectModel.list(s.relays.map { "`\($0)`" }) + "."), ""]
                if let what = s.what { out += [Markdown.inline(what), ""] }
                if !s.events.isEmpty {
                    out += ["| Event | Reducer | What it does |", "|---|---|---|"]
                    for e in s.events {
                        let said = e.doc ?? does(e.scopes)
                        out.append("| `\(e.event)` | " + (e.path.map { "[\(e.reducer)](\(link($0))#L\(e.line ?? 1))" } ?? e.reducer) + " | " + Markdown.cell(Markdown.inline(said ?? "–")) + " |")
                    }
                    out.append("")
                }
                for a in s.agents { out += ["Its `@Agent(\(a.policy)) var \(a.name): \(a.type).Agent` runs off main and streams back.", ""] }
            }
        }
        if !components.isEmpty {
            out += ["## Components", "", "| Component | Reads | Events |", "|---|---|---|"]
            for c in components {
                out.append("| \(fileLink(c.path, line: c.line)) | " + Markdown.cell(c.relays.joined(separator: ", ").nonEmpty ?? "–") + " | "
                           + Markdown.cell(c.events.map { "`\($0.event)` → \($0.reducer)" }.joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        return out
    }

    /// What a reducer does, from its code: the state its reduce and effect write, what they set off.
    private func does(_ scopes: [Int]) -> String? {
        guard let graph = model.graph, !scopes.isEmpty else { return nil }
        let facts = CodeFacts(graph: graph)
        let clauses = scopes.flatMap { g in facts.clauses(g, edges: graph.edges.filter { $0.source == g }) }
        guard !clauses.isEmpty else { return nil }
        let text = clauses.joined(separator: "; ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    // MARK: - A folder's page

    func page(_ path: String) -> String {
        let f = model.folders[path]!
        var out = ["# \(path)", ""]
        out += lede(path)
        out += overview(path, from: folder)
        out += ["\(Markdown.count(f.filesAll)) files, \(Markdown.count(f.linesAll)) lines" + (f.foldersAll > 0 ? ", in \(Markdown.count(f.foldersAll)) folder\(f.foldersAll == 1 ? "" : "s")" : "")
                + ". The folder: [\(path)/](\(link(path))).", ""]
        let tree = FolderTree(model: model)
        let kids = f.folders.map { path + "/" + $0 }.filter { tree.codeFiles($0) > 0 }
        if !kids.isEmpty {
            out += ["## Folders", "", "| Folder | What it holds | Files |", "|---|---|---|"]
            out += kids.map { "| [\(($0 as NSString).lastPathComponent)/](\(link($0))) | " + Markdown.cell(tree.line($0)) + " | \(tree.codeFiles($0)) |" }
            out.append("")
        }
        let here = { (s: ServiceFacts) in s.folder == path || s.folder.hasPrefix(path + "/") }
        out += services(model.services.filter(here), components: model.components.filter(here), from: path)
        let files = model.scan.files.filter { $0.path.hasPrefix(path + "/") }
        if !files.isEmpty {
            out += ["## Files", "", "| File | Lines | What it is |", "|---|---|---|"]
            for file in files.prefix(300) {
                var said = file.isSwift ? (model.swiftSource(file.path)?.summary ?? "") : OtherSource.summary(file)
                if said.isEmpty, let source = model.swiftSource(file.path) {
                    let declared = source.scopes.filter { $0.parent < 0 }.prefix(3).map { "\($0.keyword) `\($0.name)`" }
                    said = declared.isEmpty ? "" : "declares " + declared.joined(separator: ", ")
                }
                let shown = String(file.path.dropFirst(path.count + 1))
                out.append("| [\(Markdown.cell(shown))](\(link(file.path))) | \(file.lines) | " + Markdown.cell(Markdown.inline(said.nonEmpty ?? "–")) + " |")
            }
            if files.count > 300 { out.append("\nAnd \(files.count - 300) more files.") }
            out.append("")
        }
        if let graph = model.graph {
            let types = graph.scopes.indices.filter { g in
                graph.scopes[g].isType && graph.scopes[g].parent < 0 && !graph.scopes[g].mods.contains("private")
                    && graph.files[graph.fileOf[g]].path.hasPrefix(path + "/")
            }.sorted { (graph.scopes[$0].name.lowercased(), graph.ids[$0]) < (graph.scopes[$1].name.lowercased(), graph.ids[$1]) }
            if !types.isEmpty {
                out += ["## Types", ""]
                for g in types.prefix(200) { out.append("- " + glossaryLine(g)) }
                if types.count > 200 { out.append("- and \(types.count - 200) more, in [the glossary](Glossary.md)") }
                out.append("")
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    // MARK: - Glossary.md

    /// One type, one line: its name, what it is and where, and what its doc comment, its service or its declaration
    /// says of it.
    func glossaryLine(_ g: Int) -> String {
        let graph = model.graph!
        let scope = graph.scopes[g]
        let file = graph.files[graph.fileOf[g]]
        var said: String
        if let doc = file.docText(scope.doc) { said = SwiftSource.firstSentence(doc) }
        else if let host = (model.services + model.components).first(where: { $0.scope == g }) { said = ProjectModel.granite(host) }
        else if (file.path as NSString).lastPathComponent.hasPrefix(scope.name + "."), let what = file.what { said = SwiftSource.firstSentence(what) }
        else {
            let line = SwiftText.string(file.blankLine(scope.sig))
            if let colon = line.firstIndex(of: ":"), scope.isType {
                let conforms = line[line.index(after: colon)...].prefix { $0 != "{" }.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                said = conforms.isEmpty ? "" : "Conforms to " + ProjectModel.list(conforms.prefix(4).map { "`\($0)`" }) + "."
            } else { said = "" }
        }
        let kind = scope.mods.split(separator: " ").contains("public") || scope.mods.contains("open") ? "public \(scope.keyword)" : scope.keyword
        return "**`\(scope.name)`**, \(kind) in \(fileLink(file.path, line: scope.sig))" + (said.isEmpty ? "." : ": " + Markdown.inline(said))
    }

    func glossary() -> String {
        var out = ["# \(model.title): glossary", ""]
        guard let graph = model.graph else { return (out + ["The project declares no Swift types."]).joined(separator: "\n") + "\n" }
        let all = graph.scopes.indices.filter { g in graph.scopes[g].isType && graph.scopes[g].parent < 0 && !graph.scopes[g].mods.contains("private") }
        let chosen = all.sorted { (graph.scopes[$0].name.lowercased(), graph.ids[$0]) < (graph.scopes[$1].name.lowercased(), graph.ids[$1]) }
        out += ["Every type the project declares outside a private scope, one line each: what it is, where, and what its doc comment, its service or its declaration says.", ""]
        var letter: Character?
        for g in chosen.prefix(2_000) {
            let first = graph.scopes[g].name.uppercased().first ?? "#"
            if first != letter {
                letter = first
                out += ["", "## \(first.isLetter ? String(first) : "#")", ""]
            }
            out.append("- " + glossaryLine(g))
        }
        if chosen.count > 2_000 { out += ["", "And \(chosen.count - 2_000) more."] }
        return out.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n") + "\n"
    }

    // MARK: - Building.md

    func building() -> String {
        var out = ["# Building \(model.title)", ""]
        if !build.requirements.isEmpty { out += ["## What it needs", ""] + build.requirements.map { "- " + $0 } + [""] }
        if !build.build.isEmpty {
            out += ["## Building", ""]
            for c in build.build { out += [c.title + ":", "", "```sh", c.command, "```", ""] }
        }
        out += ["## Testing", ""]
        if build.test.isEmpty && !build.packages.contains(where: \.hasTests) { out += ["The project declares no tests: no scheme runs any, and no package has a test target.", ""] }
        for c in build.test { out += [c.title + ":", "", "```sh", c.command, "```", ""] }
        if !build.packages.isEmpty {
            out += ["## Its packages", "", "Each of the project's own packages builds and tests on its own:", ""]
            for c in build.packageCommands { out += ["- " + c.title + ": `" + c.command + "`"] }
            out.append("")
        }
        for x in model.manifest.xcode where !x.packages.isEmpty {
            out += ["## Swift packages of \(x.path)", "", "| Package | From | Requirement |", "|---|---|---|"]
            out += x.packages.map { "| \($0.name) | " + ($0.url ?? $0.path ?? "–") + " | " + ($0.requirement ?? "–") + " |" }
            out.append("")
        }
        if let p = model.manifest.package, !p.dependencies.isEmpty {
            out += ["## Dependencies of Package.swift", "", "| Package | From | Requirement |", "|---|---|---|"]
            out += p.dependencies.map { "| \($0.name) | " + ($0.url ?? $0.path ?? "–") + " | " + ($0.requirement ?? "–") + " |" }
            out.append("")
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}
