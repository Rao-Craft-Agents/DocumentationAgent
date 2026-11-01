//  WHAT: One call, from the input to the files: every problem with the input found first (folders that do not exist,
//        an output outside the project, a trail step that names nothing), then the project read once, the files of the
//        make planned, the model asked for the prose (when the host has one), and everything written whole or not at
//        all. Answers where the files are and what was left out.
//  PIN:  REFUSED WHOLE. A call the agent cannot honour says every reason at once and writes nothing.

import Foundation
import GraniteAgents

struct DocumentationRun: Sendable {
    let input: DocumentationAgent.Input
    let host: AgentHost
    let yield: @Sendable (DocumentationFrame) -> Void

    static let defaultInto: [DocumentationMake: String] = [.readme: ".", .markdown: "Docs", .site: "Docs/site"]

    func run() async throws -> DocumentationResult {
        let files = AgentFiles(directory: input.directory ?? host.directory)
        let root = files.root
        let rootPath = root.path
        var reasons: [String] = []
        var notes: [String] = []

        // MARK: What the call asks, checked first
        let intoText = input.into?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? Self.defaultInto[input.make]!
        let intoURL = files.resolve(intoText)
        let into = ProjectScan.relative(intoURL.path, root: rootPath).nonEmpty ?? "."
        if into.hasPrefix("/") { reasons.append("`into` is \(intoText), outside the project at \(rootPath): the docs are written inside the project") }
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: intoURL.path, isDirectory: &isFolder), !isFolder.boolValue {
            reasons.append("`into` is \(intoText), which is a file, not a folder")
        }
        var sources: [String] = []
        for source in input.sources ?? [] where !source.trimmingCharacters(in: .whitespaces).isEmpty {
            let rel = ProjectScan.relative(source.trimmingCharacters(in: .whitespaces), root: rootPath)
            if rel.hasPrefix("/") { reasons.append("the source \(source) is outside the project"); continue }
            if !FileManager.default.fileExists(atPath: rel.isEmpty ? rootPath : rootPath + "/" + rel) { reasons.append("the source \(source) does not exist in the project"); continue }
            sources.append(rel)
        }
        if let rounds = input.rounds, !(1...6).contains(rounds) { reasons.append("`rounds` is \(rounds); give 1 to 6") }
        if let title = input.title, title.count > 80 || title.contains("\n") { reasons.append("`title` must be one line of at most 80 characters") }
        if let tagline = input.tagline, tagline.count > 200 || tagline.contains("\n") { reasons.append("`tagline` must be one line of at most 200 characters") }
        let features = (input.features ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if features.count > 12 { reasons.append("`features` has \(features.count) lines; give at most 12") }
        for line in features where line.count > 240 || line.contains("\n") { reasons.append("the feature `\(line.prefix(40))…` must be one line of at most 240 characters") }
        if input.make != .site {
            if !(input.trails ?? []).isEmpty { notes.append("`trails` are walked by the site only; this \(input.make.rawValue) has none") }
            if input.ask == true { notes.append("the ask orb is the site's; this \(input.make.rawValue) has none") }
        }
        if input.make != .readme {
            if input.license != nil { notes.append("a licence is named and written by the README only") }
            if !features.isEmpty { notes.append("`features` are the README's; this \(input.make.rawValue) has none") }
        }
        guard reasons.isEmpty else { throw DocumentationError.refused(reasons) }

        // MARK: The project, read once
        let started = Date()
        let readmePath = into == "." ? "README.md" : into + "/README.md"
        let exclude = input.make == .site ? [into] : []
        let model = ProjectModel(root: root, title: input.title, sources: sources, exclude: exclude)
        guard !model.scan.files.isEmpty || !model.scan.docs.isEmpty else {
            throw DocumentationError.nothing(sources.isEmpty ? (rootPath as NSString).lastPathComponent : sources.joined(separator: ", "))
        }
        let lines = model.scan.files.reduce(0) { $0 + $1.lines }
        yield(.read(files: model.scan.files.count, lines: lines))
        yield(.parsed(declarations: model.graph?.scopes.count ?? 0, calls: model.graph?.edges.count ?? 0))
        host.note("read \(model.scan.files.count) files of code (\(model.swift.count) Swift, \(lines) lines) and \(model.scan.docs.count) docs"
                  + String(format: " in %.1f s", Date().timeIntervalSince(started)))
        if !model.scan.skipped.isEmpty {
            notes.append("\(model.scan.skipped.count) file\(model.scan.skipped.count == 1 ? " was" : "s were") left out, the first \(model.scan.skipped[0].path): \(model.scan.skipped[0].why)")
        }
        let unbalanced = model.swift.filter { !$0.balanced || $0.problem != nil }
        if !unbalanced.isEmpty {
            notes.append("\(unbalanced.count) Swift file\(unbalanced.count == 1 ? "" : "s") could not be walked whole (an unclosed string or an `#if` that opens a brace twice), the first \(unbalanced[0].path)")
        }
        let build = BuildFacts(model.manifest)
        let prose = ProseWriter(model: host.model, rounds: input.rounds ?? 3, note: host.note)
        let place = { (name: String) -> URL in files.resolve(into == "." ? name : into + "/" + name) }
        var planned: [(url: URL, text: String)] = []
        var main: URL
        var trails: [Trail] = []

        switch input.make {
        case .site:
            if let graph = model.graph {
                let builder = TrailBuilder(graph: graph, model: model)
                if let lines = input.trails, !lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    let made = builder.trails(from: lines)
                    if !made.reasons.isEmpty { throw DocumentationError.refused(made.reasons) }
                    trails = made.trails
                } else {
                    trails = builder.derived()
                    if trails.isEmpty { notes.append("no trail: the code declares no Granite services and the call named none") }
                }
            } else if !(input.trails ?? []).isEmpty {
                throw DocumentationError.refused(["the project has no Swift for the trails to walk"])
            } else {
                notes.append("no call graph and no trail: the project has no Swift to walk; its files have pages and search")
            }
            let ask = input.ask ?? false
            planned.append((place("index.html"), SiteAssets.page(title: model.title, ask: ask)))
            for asset in SiteAssets.files(ask: ask) { planned.append((place(asset.name), asset.text)) }
            planned.append((place("data.js"), SiteData.script(model, trails: trails, site: into == "." ? "" : into, tagline: input.tagline, ask: ask, build: build)))
            for script in ExplorerData.scripts(model, trails: trails) { planned.append((place("explorer/" + script.file), script.text)) }
            planned.append((place(".gitignore"), "# The ask orb's key lives here, on this machine only.\nlocal/\n"))
            main = place("index.html")
            if ask { notes.append("the ask orb answers once the person writes a key into \(into)/local/ask.js; none was written") }
        case .readme:
            var writer = ReadmeWriter(model: model, build: build, folder: into, tagline: input.tagline, features: features.isEmpty ? nil : features)
            let digest = ProseDigest.project(model, leaving: [readmePath])
            host.note(host.model == nil ? "no model: the README is written without its opening and features" : "asking the model for the README's opening" + (features.isEmpty ? " and features" : ""))
            let outcome = await prose.opening(model.title, digest: digest, features: features.isEmpty)
            if let answer = outcome.answer { writer.opening = answer } else {
                notes.append("the README's opening paragraph" + (features.isEmpty ? " and feature list are" : " is") + " left out: " + (outcome.why ?? "no answer"))
                if let about = model.folders["."]?.about, about.from != "readme", let source = about.source, source != readmePath {
                    writer.about = (about.text, source)
                }
            }
            let licenseFile = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE"].first { FileManager.default.fileExists(atPath: rootPath + "/" + $0) }
            if let license = input.license {
                if let licenseFile {
                    let existing = (try? String(contentsOfFile: rootPath + "/" + licenseFile, encoding: .utf8)).flatMap(LicenseText.named)
                    writer.license = (existing ?? license.rawValue, licenseFile)
                    if let existing, existing != license.rawValue { notes.append("the project's \(licenseFile) is \(existing), not \(license.rawValue); it was kept, and the README names it") }
                } else {
                    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
                    let holder = ProjectModel.git(root, ["config", "user.name"]) ?? "the \(model.title) authors"
                    planned.append((files.resolve("LICENSE"), LicenseText.text(license, year: year, holder: holder)))
                    writer.license = (license.rawValue, "LICENSE")
                }
            } else if let licenseFile, let named = (try? String(contentsOfFile: rootPath + "/" + licenseFile, encoding: .utf8)).flatMap(LicenseText.named) {
                writer.license = (named, licenseFile)
            }
            main = place("README.md")
            planned.insert((main, writer.text()), at: 0)
        case .markdown:
            var writer = MarkdownWriter(model: model, build: build, folder: into)
            if host.model != nil {
                for folder in writer.topFolders.prefix(12) {
                    host.note("asking the model for \(folder)/'s overview")
                    let outcome = await prose.overview(model.title, folder: folder, digest: ProseDigest.folder(model, path: folder))
                    if let answer = outcome.answer { writer.overviews[folder] = answer } else { notes.append("\(folder)/'s overview is left out: " + (outcome.why ?? "no answer")) }
                }
                if writer.topFolders.count > 12 { notes.append("\(writer.topFolders.count - 12) folders past the first 12 have no overview") }
            } else {
                notes.append("the folders' overviews are left out: the host offers no model")
            }
            for page in writer.files() { planned.append((place(page.name), page.text)) }
            main = place("Architecture.md")
        }

        try Task.checkCancellation()
        let written = try files.write(planned)
        if input.make == .site { notes += Self.removeStale(in: place("explorer"), keeping: Set(planned.map(\.url.path)), ask: input.ask ?? false, site: place(".")) }
        host.note("wrote \(written.count) file\(written.count == 1 ? "" : "s") into \(files.relative(place(".")))" + String(format: " in %.1f s", Date().timeIntervalSince(started)))
        return DocumentationResult(path: main.path, paths: written, make: input.make.rawValue,
                                   open: input.make == .site ? main.absoluteURL.absoluteString : nil, files: model.scan.files.count, swift: model.swift.count,
                                   services: model.services.count, trails: trails.map(\.title), notes: notes)
    }

    /// The Explorer's scripts an earlier run wrote that this one did not, and an orb this one does not carry: removed,
    /// so the site holds only what its page loads.
    static func removeStale(in folder: URL, keeping: Set<String>, ask: Bool, site: URL) -> [String] {
        let manager = FileManager.default
        var removed: [String] = []
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".js") {
            let url = folder.appendingPathComponent(name)
            guard !keeping.contains(url.path), let head = try? String(contentsOf: url, encoding: .utf8).prefix(200), head.contains(ProjectScan.generatedMark) else { continue }
            if (try? manager.removeItem(at: url)) != nil { removed.append(name) }
        }
        let orb = site.appendingPathComponent("ask.js")
        if !ask, let text = try? String(contentsOf: orb, encoding: .utf8), text == SiteAssets.ask, (try? manager.removeItem(at: orb)) != nil { removed.append("ask.js") }
        return removed.isEmpty ? [] : ["removed \(removed.count) file\(removed.count == 1 ? "" : "s") an earlier site wrote and this one does not load: " + removed.joined(separator: ", ")]
    }
}
