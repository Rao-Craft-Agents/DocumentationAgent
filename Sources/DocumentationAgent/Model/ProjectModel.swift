//  WHAT: The project, read once for every make: its files, its manifests, every Swift file walked, the call graph with
//        its Granite flows, the services and components ranked, the folders as a spine with what each one is, and the
//        commit it was read at. The writers read this and nothing else.

import Foundation

final class ProjectModel: @unchecked Sendable {
    let root: URL
    let title: String
    let scan: ProjectScan
    let manifest: ProjectManifest
    let graph: CallGraph?
    /// The Swift files, walked, in path order.
    let swift: [SwiftSource]
    let services: [ServiceFacts]
    let components: [ServiceFacts]
    /// Circles among the services' relays, as the ranking cut them.
    let cycles: [String]
    private(set) var folders: [String: FolderFacts] = [:]
    /// The commit the project is at, when it is a git repository.
    let head: String?
    /// The `@main` type and the declaration the app starts in, when the code has one.
    let entry: Int?

    init(root: URL, title: String?, sources: [String], exclude: [String]) {
        self.root = root
        scan = ProjectScan(root: root, sources: sources, exclude: exclude)
        let packageFiles = scan.files.filter { $0.name == "Package.swift" }.map(\.path)
        manifest = ProjectManifest(root: root, packageFiles: packageFiles)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? manifest.name(folder: root.lastPathComponent)
        let packages = manifest.packages
        let walked = scan.swiftFiles.map { SwiftSource(text: $0.text, path: $0.path, module: Self.module(of: $0.path, packages: packages, project: title ?? root.lastPathComponent)) }
        if walked.isEmpty {
            graph = nil
            swift = []
        } else {
            // A module of its own: each package target's folder, then each local package's (its demos and tools).
            let modules = packages.flatMap { p in p.targets.map { p.sourceFolder($0) + "/" } } + manifest.localPackages.map { $0.folder + "/" }
            let built = CallGraph(walked, modules: modules)
            built.build()
            graph = built
            swift = built.files
        }
        head = Self.git(root, ["rev-parse", "--short", "HEAD"])
        var services: [ServiceFacts] = [], components: [ServiceFacts] = []
        var cycles: [String] = []
        if let graph, !graph.granite.hosts.isEmpty {
            let ranked = graph.granite.ranks()
            cycles = graph.granite.cycles
            for (name, rank, reaches) in ranked { services.append(Self.facts(name, graph: graph, rank: rank, reaches: reaches)) }
            for name in graph.granite.components { components.append(Self.facts(name, graph: graph, rank: 0, reaches: [])) }
        }
        self.services = services
        self.components = components
        self.cycles = cycles
        // The `@main` type: the attribute on its own line or before the keyword, which the walk folds into its lines. Of
        // several (a package's demo app beside the app), the project's own: outside its local packages, not a demo, an
        // example or a test, the shallowest.
        let packageFolders = manifest.localPackages.map { $0.folder + "/" }
        entry = graph.flatMap { graph in
            let mains = graph.scopes.indices.filter { g in
                let scope = graph.scopes[g]
                guard scope.parent < 0, scope.isType else { return false }
                if scope.attrs.contains("@main") { return true }
                let lines = graph.files[graph.fileOf[g]].lines
                return (scope.decl...scope.sig).contains { n in
                    let line = lines[n - 1].trimmingCharacters(in: .whitespaces)
                    return line == "@main" || line.hasPrefix("@main ")
                }
            }
            func rank(_ g: Int) -> (Int, Int, Int, String) {
                let path = graph.files[graph.fileOf[g]].path
                let aside = path.split(separator: "/").contains { ["demo", "demos", "example", "examples", "sample", "samples", "tests", "test"].contains($0.lowercased()) }
                return (packageFolders.contains { path.hasPrefix($0) } ? 1 : 0, aside ? 1 : 0, path.split(separator: "/").count, path)
            }
            return mains.min { rank($0) < rank($1) }
        }
        folders = buildFolders()
    }

    /// The module a Swift file belongs to: the target its `Sources/<X>` or `Tests/<X>` names, else its top folder.
    static func module(of path: String, packages: [SwiftPackage], project: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let at = parts.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }), at + 2 < parts.count { return parts[at + 1] }
        return parts.count > 1 ? parts[0] : project
    }

    static func git(_ root: URL, _ arguments: [String]) -> String? {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private static func facts(_ name: String, graph: CallGraph, rank: Int, reaches: [String]) -> ServiceFacts {
        let granite = graph.granite!
        let host = granite.hosts[name]!
        let g = host.scope
        let file = graph.files[graph.fileOf[g]]
        let folder = (file.path as NSString).deletingLastPathComponent
        let events = host.events.map { event -> ServiceFacts.Event in
            let type = granite.reducerType(name, event.reducer)
            let typeFile = type.map { graph.files[graph.fileOf[$0]] }
            let doc = type.flatMap { t in typeFile?.docText(graph.scopes[t].doc).map(SwiftSource.firstSentence) }
            return ServiceFacts.Event(event: event.event, reducer: event.reducer, path: typeFile?.path, line: type.map { graph.scopes[$0].sig },
                                      doc: doc, scopes: granite.reducer(name, event.event), declared: event.line)
        }
        var relays: Set<String> = []
        let module = graph.moduleOf[graph.fileOf[g]]
        for (key, held) in granite.handles where key == granite.handleKey(module, name) || key.hasPrefix(granite.handleKey(module, name + ".")) {
            relays.formUnion(held.values)
        }
        relays.remove(name)
        let what = file.docText(graph.scopes[g].doc) ?? file.what
        return ServiceFacts(name: name, isComponent: host.isComponent, scope: g, path: file.path, line: graph.scopes[g].sig, module: file.module,
                            folder: folder.isEmpty ? "." : folder, what: what, events: events, relays: relays.sorted(), reaches: reaches, rank: rank,
                            agents: host.agents.map { ServiceFacts.Agent(name: $0.name, type: $0.type, policy: $0.policy, run: $0.run) })
    }

    // MARK: - The spine

    var allFiles: [ProjectFile] { (scan.files + scan.docs).sorted { $0.path < $1.path } }

    func swiftSource(_ path: String) -> SwiftSource? {
        guard let graph else { return nil }
        return sourceIndex[path].map { graph.files[$0] }
    }

    private lazy var sourceIndex: [String: Int] = {
        var index: [String: Int] = [:]
        for (i, f) in swift.enumerated() { index[f.path] = i }
        return index
    }()

    private func buildFolders() -> [String: FolderFacts] {
        var folders: [String: FolderFacts] = [:]
        func folder(_ path: String) {
            guard folders[path] == nil else { return }
            let parent: String? = path == "." ? nil : (path.contains("/") ? (path as NSString).deletingLastPathComponent : ".")
            folders[path] = FolderFacts(path: path, name: path == "." ? title : (path as NSString).lastPathComponent, parent: parent)
            if let parent {
                folder(parent)
                folders[parent]!.folders.append((path as NSString).lastPathComponent)
            }
        }
        folder(".")
        for file in allFiles {
            let here = file.folder
            folder(here)
            folders[here]!.files.append(file.name)
            folders[here]!.files1 += 1
            folders[here]!.lines1 += file.lines
            var at: String? = here
            while let p = at {
                folders[p]!.filesAll += 1
                folders[p]!.linesAll += file.lines
                at = folders[p]!.parent
            }
        }
        for path in folders.keys {
            folders[path]!.folders.sort()
            folders[path]!.files.sort()
            var at = folders[path]!.parent
            while let p = at {
                folders[p]!.foldersAll += 1
                at = folders[p]!.parent
            }
        }
        let packages = manifest.packages
        for path in folders.keys.sorted() {
            var facts = folders[path]!
            if path == "." {
                facts.kind = "root"
            } else if let package = packages.first(where: { $0.folder == path }) {
                facts.kind = "package"
                facts.package = package.name
            } else if let package = packages.first(where: { p in p.targets.contains { p.sourceFolder($0) == path } }) {
                facts.kind = "target"
                facts.package = package.name
            } else if FolderFacts.groups.contains(facts.name), facts.parent != nil, facts.parent != "." {
                facts.kind = "group"
            }
            facts.services = services.filter { $0.folder == path || $0.folder.hasPrefix(path == "." ? "" : path + "/") }.map(\.name)
            facts.components = components.filter { $0.folder == path || $0.folder.hasPrefix(path == "." ? "" : path + "/") }.map(\.name)
            (facts.about, facts.rootType) = about(of: facts)
            folders[path] = facts
        }
        for path in folders.keys.sorted() {
            folders[path]!.holds = holds(folders[path]!, in: folders)
        }
        return folders
    }

    /// What a folder is, read off the code, and its root type.
    private func about(of folder: FolderFacts) -> (FolderFacts.About?, FolderFacts.RootType?) {
        let prefix = folder.path == "." ? "" : folder.path + "/"
        var rootType: FolderFacts.RootType?
        // The root type: `<Folder>.swift` here, or a target's type of its name, or the type the folder is named for.
        let named = folder.kind == "root" ? nil : folder.name
        if let named, let graph {
            let candidates = (graph.types[named] ?? []).filter { graph.scopes[$0].parent < 0 && graph.files[graph.fileOf[$0]].path.hasPrefix(prefix) }
            let direct = candidates.first { (graph.files[graph.fileOf[$0]].path as NSString).deletingLastPathComponent == folder.path }
            if let g = direct ?? candidates.first {
                let file = graph.files[graph.fileOf[g]]
                rootType = FolderFacts.RootType(name: named, path: file.path, line: graph.scopes[g].sig, kind: graph.scopes[g].keyword)
                if let doc = file.docText(graph.scopes[g].doc) {
                    return (FolderFacts.About(text: doc, from: "doc", source: file.path, line: graph.scopes[g].sig, type: named), rootType)
                }
                if let what = file.what { return (FolderFacts.About(text: what, from: "what", source: file.path, line: 1, type: named), rootType) }
            }
            if rootType == nil, let file = swiftSource(prefix + named + ".swift"), let what = file.what {
                return (FolderFacts.About(text: what, from: "what", source: file.path, line: 1, type: nil), nil)
            }
        }
        if folder.kind == "root" {
            if let package = manifest.package, let text = package.about {
                return (FolderFacts.About(text: text, from: "package", source: "Package.swift", line: 1, type: nil), nil)
            }
            if let entry, let graph {
                let file = graph.files[graph.fileOf[entry]]
                if let text = file.docText(graph.scopes[entry].doc) ?? file.what {
                    return (FolderFacts.About(text: text, from: "doc", source: file.path, line: graph.scopes[entry].sig, type: graph.scopes[entry].name), nil)
                }
            }
        }
        if folder.kind == "package", let package = manifest.packages.first(where: { $0.folder == folder.path }), let text = package.about {
            return (FolderFacts.About(text: text, from: "package", source: prefix + "Package.swift", line: 1, type: nil), rootType)
        }
        if let host = (services + components).first(where: { $0.folder == folder.path && $0.name == folder.name }) {
            return (FolderFacts.About(text: Self.granite(host), from: "granite", source: host.path, line: host.line, type: host.name), rootType)
        }
        if let readme = scan.docs.first(where: { $0.folder == folder.path && $0.name.lowercased().hasPrefix("readme") }),
           let text = Markdown.firstParagraph(readme.text) {
            return (FolderFacts.About(text: text, from: "readme", source: readme.path, line: nil, type: nil), rootType)
        }
        if folder.kind == "group", let parent = folder.parent, let parentName = parent.split(separator: "/").last {
            return (FolderFacts.About(text: "The \(folder.name.lowercased()) of \(parentName), one type a file.", from: "group", source: nil, line: nil, type: nil), rootType)
        }
        return (nil, rootType)
    }

    /// What a folder holds, from its code: the services, components, packages or targets in the folders under it, else
    /// the types its own files declare, else its folders, else its files by language.
    private func holds(_ folder: FolderFacts, in folders: [String: FolderFacts]) -> String? {
        let path = folder.path
        let parentOf = { (p: String) -> String in p.contains("/") ? (p as NSString).deletingLastPathComponent : "." }
        func named(_ names: [String], _ one: String, _ many: String) -> String {
            let shown = names.prefix(5).map { "`\($0)`" }
            return "\(names.count) \(names.count == 1 ? one : many): " + ProjectModel.list(shown + (names.count > 5 ? ["\(names.count - 5) more"] : []))
        }
        var parts: [String] = []
        let services = self.services.filter { parentOf($0.folder) == path }.map(\.name)
        if !services.isEmpty { parts.append(named(services, "Granite service", "Granite services")) }
        let components = self.components.filter { parentOf($0.folder) == path }.map(\.name)
        if !components.isEmpty { parts.append(named(components, "Granite component", "Granite components")) }
        let packages = manifest.localPackages.filter { parentOf($0.folder) == path }.map(\.name)
        if !packages.isEmpty { parts.append(named(packages, "Swift package", "Swift packages")) }
        let targets = manifest.packages.flatMap { p in p.targets.filter { parentOf(p.sourceFolder($0)) == path }.map(\.name) }
        if !targets.isEmpty { parts.append(named(targets, "target", "targets")) }
        if !parts.isEmpty { return ProjectModel.list(parts) }
        let direct = swift.filter { (($0.path as NSString).deletingLastPathComponent.nonEmpty ?? ".") == path }
        var declared: [String] = []
        for file in direct { for scope in file.scopes where scope.parent < 0 && scope.isType && !declared.contains(scope.name) { declared.append(scope.name) } }
        if !declared.isEmpty { return "declares " + ProjectModel.list(declared.prefix(5).map { "`\($0)`" } + (declared.count > 5 ? ["\(declared.count - 5) more"] : [])) }
        let kids = folder.folders.filter { name in folders[path == "." ? name : path + "/" + name] != nil }
        if !kids.isEmpty { return named(kids.map { $0 + "/" }, "folder", "folders") }
        let prefix = path == "." ? "" : path + "/"
        let files = (scan.files + scan.docs).filter { $0.path.hasPrefix(prefix) }
        guard !files.isEmpty else { return nil }
        let languages = Dictionary(grouping: files, by: \.language).sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        return ProjectModel.list(languages.prefix(2).map { "\($0.value.count) \($0.key) file\($0.value.count == 1 ? "" : "s")" })
    }

    /// A service or component said from its declarations: what it is, its events, what it holds a relay to.
    static func granite(_ host: ServiceFacts) -> String {
        let kind = host.isComponent ? "a Granite component" : "a Granite service"
        var text = "\(host.name) is \(kind)"
        if host.events.isEmpty { text += " whose center declares no events" }
        else { text += "; its center declares \(host.events.count) event\(host.events.count == 1 ? "" : "s"): " + Self.list(host.events.map { "`\($0.event)`" }) }
        if !host.relays.isEmpty { text += ", and it \(host.isComponent ? "reads" : "holds a relay to") " + Self.list(host.relays.map { "`\($0)`" }) }
        return text + "."
    }

    /// `a`, `a and b`, `a, b and c`.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
