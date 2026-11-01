//  WHAT: The Explorer's data, `explorer/index.js` and one script a folder at the project's top: every file of code
//        verbatim, its declarations as compact rows, the call graph's edges with their tiers and flows, the services and
//        components with their events, and the trails. The page loads them the first time the Explorer opens.
//  PIN:  THE SAME NUMBERS ON BOTH SIDES. A declaration's number is its place across the Swift files in path order; the
//        index lists the files in the order the page reads them, unit by unit, and the page's self-check holds the two
//        to each other.

import Foundation

enum ExplorerData {
    static let flows = ["event", "relay", "own", "agent", "frames", "reply", "handler", "protocol"]

    struct Unit {
        let name: String
        let slug: String
        var files: [ProjectFile]
    }

    /// The units the files load in: one a folder at the top, the root's own files first.
    static func units(_ model: ProjectModel) -> [Unit] {
        var byName: [String: [ProjectFile]] = [:]
        for file in model.scan.files { byName[file.topFolder, default: []].append(file) }
        let names = byName.keys.sorted { a, b in a == "." ? b != "." : b == "." ? false : a.lowercased() < b.lowercased() }
        var slugs: Set<String> = ["index"]
        return names.map { name in
            var base = name == "." ? "root" : String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
            if base.isEmpty { base = "unit" }
            var slug = base, n = 2
            while !slugs.insert(slug.lowercased()).inserted { slug = "\(base)-\(n)"; n += 1 }
            return Unit(name: name, slug: slug, files: byName[name]!)
        }
    }

    static func script(_ name: String, _ value: JSONValue) -> String {
        SiteData.header + "window.DOCS_EXPLORER = window.DOCS_EXPLORER || {};\nwindow.DOCS_EXPLORER.sources = window.DOCS_EXPLORER.sources || {};\n"
            + "window.DOCS_EXPLORER.sources[" + JSONValue.string(name).text + "] = " + value.text + ";\n"
    }

    /// Every script: `index` first, then one a unit, by file name.
    static func scripts(_ model: ProjectModel, trails: [Trail]) -> [(file: String, text: String)] {
        let units = units(model)
        let graph = model.graph
        var indexFiles: [JSONValue] = []
        var out: [(String, String)] = []
        var unitScripts: [(String, String)] = []
        for unit in units {
            var records: [JSONValue] = []
            for file in unit.files {
                if file.isSwift, let source = model.swiftSource(file.path) {
                    var record = source.record(first: source.first)
                    if case .object(var pairs) = record {
                        pairs.insert(("module", .string(source.module)), at: 1)
                        pairs.insert(("lang", .string("Swift")), at: 2)
                        record = .object(pairs)
                    }
                    records.append(record)
                    indexFiles.append(.object([("path", .string(file.path)), ("module", .string(unit.name)), ("first", .int(source.first)),
                                               ("scopes", .int(source.scopes.count)), ("lines", .int(source.lineCount)), ("bytes", .int(file.bytes))]))
                } else {
                    let lines = file.text.components(separatedBy: "\n").count - (file.text.hasSuffix("\n") ? 1 : 0)
                    records.append(.object([("path", .string(file.path)), ("module", .string(file.topFolder == "." ? model.title : file.topFolder)),
                                            ("lang", .string(file.language)), ("lines", .int(lines)), ("bytes", .int(file.bytes)), ("header", .null),
                                            ("summary", .string(OtherSource.summary(file))), ("marks", .array([])), ("first", .int(0)),
                                            ("scopes", .array([])), ("text", .string(file.text))]))
                    indexFiles.append(.object([("path", .string(file.path)), ("module", .string(unit.name)), ("first", .int(0)), ("scopes", .int(0)),
                                               ("lines", .int(lines)), ("bytes", .int(file.bytes))]))
                }
            }
            unitScripts.append((unit.slug + ".js", script(unit.name, .object([("module", .string(unit.name)), ("files", .array(records))]))))
        }
        var kinds: [String: Int] = [:]
        for scope in graph?.scopes ?? [] { kinds[scope.kind, default: 0] += 1 }
        let edges = graph?.edges ?? []
        let onTrails = Set(trails.flatMap { $0.steps.flatMap { $0.entries.map(\.scope) } })
        let counts: JSONValue = .object([
            ("files", .int(model.scan.files.count)), ("lines", .int(model.scan.files.reduce(0) { $0 + $1.lines })),
            ("bytes", .int(model.scan.files.reduce(0) { $0 + $1.bytes })), ("scopes", .int(graph?.scopes.count ?? 0)),
            ("funcs", .int(kinds["f"] ?? 0)), ("inits", .int(kinds["i"] ?? 0)),
            ("types", .int(["S", "C", "E", "A", "P"].reduce(0) { $0 + (kinds[$1] ?? 0) })),
            ("edges", .object(CallGraph.tiers.enumerated().map { tier in (tier.element, .int(edges.filter { $0.tier == tier.offset }.count)) })),
            ("flows", .object(flows.map { kind in (kind, .int(edges.filter { $0.via == kind }.count)) })),
        ])
        let sample: [JSONValue] = (graph?.ids.indices ?? 0..<0).filter { onTrails.contains($0) || $0 % 50 == 0 }.map { .array([.int($0), .string(graph!.ids[$0])]) }
        func host(_ s: ServiceFacts, reaches: [String]) -> JSONValue {
            .object([("name", .string(s.name)), ("module", .string(s.module)), ("g", .int(s.scope)), ("rank", .int(s.rank)), ("relays", .strings(reaches)),
                     ("events", .array(s.events.map { .array([.string($0.event), .string($0.reducer), .ints($0.scopes)]) })),
                     ("agents", .array(s.agents.map { .array([.string($0.name), .string($0.type), .string($0.policy), .optional($0.run)]) }))])
        }
        let loop: JSONValue = .object([
            ("title", .string("Trails")),
            ("subtitle", .string(trails.isEmpty ? "none" : "\(trails.count) walk\(trails.count == 1 ? "" : "s") through the code, in the order it runs")),
            ("say", .string(trails.isEmpty ? "No trail: the code declares no Granite services to derive one from, and the call named none."
                            : "Each trail walks declarations in the order the code runs them; each entry says how the one before reaches it.")),
        ])
        let index: JSONValue = .object([
            ("commit", .optional(model.head)), ("modules", .strings(units.map(\.name))),
            ("units", .object(units.map { ($0.name, .string($0.slug)) })), ("files", .array(indexFiles)), ("counts", counts), ("sample", .array(sample)),
            ("edges", .array(edges.map { e in
                .array([.int(e.source), .int(e.target), .int(e.tier), .int(e.line), .int(e.count)] + (e.via.map { [.string($0)] } ?? []))
            })),
            ("flows", .strings(flows)),
            ("services", .array(model.services.map { host($0, reaches: $0.reaches) })),
            ("components", .array(model.components.map { host($0, reaches: $0.relays) })),
            ("trails", .array(trails.map(\.json))), ("loop", loop),
        ])
        out.append(("index.js", script("index", index)))
        return out + unitScripts
    }
}
