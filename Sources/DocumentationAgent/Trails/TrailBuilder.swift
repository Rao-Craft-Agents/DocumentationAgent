//  WHAT: The trails a site walks: the call's own lines, each step resolved to the declarations it names, or, when the
//        call gives none, trails derived from the Granite flows: boot (from the app's `@main` through every event and
//        relay it sets off), then each service's events in the order its center declares them. Each entry is noted from
//        the code, and how it is reached is worked out from the graph's edges.
//  PIN:  A STEP THAT NAMES NOTHING IS REFUSED. A trail is the person's word on how the code runs; a step that matches
//        no declaration, or several the step cannot tell apart, is a reason the call writes nothing, said with the
//        names it could have meant.

import Foundation

struct TrailBuilder {
    let graph: CallGraph
    let model: ProjectModel
    /// The edges out of each declaration, read once.
    let outgoing: [Int: [CallGraph.Edge]]

    init(graph: CallGraph, model: ProjectModel) {
        self.graph = graph
        self.model = model
        outgoing = CodeFacts.outgoing(graph)
    }

    static let maxServiceTrails = 16
    static let flowKinds: Set<String> = ["event", "relay", "own", "agent", "frames", "reply", "handler"]

    // MARK: - The call's own trails

    /// The trails the lines name, and every reason a line or a step cannot be walked.
    func trails(from lines: [String]) -> (trails: [Trail], reasons: [String]) {
        var reasons: [String] = [], trails: [Trail] = []
        var marks: Set<String> = [], ids: Set<String> = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            switch TrailLine.parse(line) {
            case .failure(let error): reasons.append(error.description)
            case .success(let parsed):
                var steps: [Trail.Step] = []
                for (i, step) in parsed.steps.enumerated() {
                    switch resolve(step) {
                    case .failure(let error): reasons.append("in the trail `\(parsed.name)`, \(error.description)")
                    case .success(let scopes): steps.append(Trail.Step(n: i + 1, title: step, entries: scopes.map { entry($0, cite: nil) }))
                    }
                }
                guard steps.count == parsed.steps.count else { continue }
                var trail = Trail(id: Self.unique(Self.slug(parsed.name), &ids), mark: Self.mark(parsed.name, &marks), title: parsed.name,
                                  subtitle: "\(steps.count) steps, as the call named them",
                                  say: "A walk through the code the person named: each step is a declaration, and each says how it is reached from one before it.",
                                  steps: steps)
                hops(&trail)
                trails.append(trail)
            }
        }
        return (trails, reasons)
    }

    /// The declarations a step names: a reducer's reduce and effect, an init, a member, a type, or a function.
    func resolve(_ raw: String) -> Result<[Int], TrailError> {
        var step = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        var labels: String?
        if let open = step.firstIndex(of: "(") {
            let inside = step[open...]
            labels = inside == "()" ? "()" : String(inside)
            step = String(step[..<open])
        }
        guard !step.isEmpty else { return .failure(TrailError("`\(raw)` names no declaration")) }
        let last = String(step.split(separator: ".").last ?? Substring(step))
        func matches(_ g: Int) -> Bool {
            let q = graph.qualified[g]
            guard q == step || q.hasSuffix("." + step) else { return false }
            guard let labels, labels != "()" else { return true }
            return "(" + graph.scopes[g].labels.map { $0 + ":" }.joined() + ")" == labels
        }
        if last == "init", step.contains(".") {
            let owner = String(step.dropLast(5))
            let inits = graph.scopes.indices.filter { g in
                graph.scopes[g].kind == "i" && graph.parentOf(g).map { p in graph.qualified[p] == owner || graph.qualified[p].hasSuffix("." + owner) } == true
                    && (labels == nil || labels == "()" || "(" + graph.scopes[g].labels.map { $0 + ":" }.joined() + ")" == labels)
            }
            if let first = inits.first { return .success([first]) }
        }
        var found = graph.scopes.indices.filter(matches)
        if found.count > 1 {
            let types = found.filter { graph.scopes[$0].isType }
            if !types.isEmpty { found = types }
        }
        if found.count > 1 {
            let withBody = found.filter { graph.scopes[$0].braceOffset != nil && graph.scopes[$0].kind != "X" }
            if !withBody.isEmpty { found = withBody }
        }
        guard !found.isEmpty else {
            let near = graph.scopes.indices.filter { graph.scopes[$0].name == last }.prefix(3).map { graph.qualified[$0] }
            return .failure(TrailError("`\(raw)` names no declaration in the code" + (near.isEmpty ? "" : "; it has " + ProjectModel.list(near.map { "`\($0)`" }))))
        }
        if found.count > 1 {
            return .failure(TrailError("`\(raw)` names \(found.count) declarations: " + ProjectModel.list(found.prefix(3).map { "`\(graph.ids[$0])`" }) + "; add the argument labels or the type"))
        }
        let g = found[0]
        if graph.scopes[g].isType {
            let parts = ["reduce", "effect"].flatMap { part in graph.typeMembers(graph.scopes[g].simpleName, part).filter { graph.parentOf($0) == g || graph.qualified[$0] == graph.qualified[g] + "." + part } }
            if !parts.isEmpty { return .success(parts) }
        }
        return .success([g])
    }

    // MARK: - Trails from the Granite flows

    /// Boot, from the app's entry through the events and relays it sets off; then each service's events.
    func derived() -> [Trail] {
        var trails: [Trail] = []
        var marks: Set<String> = [], ids: Set<String> = []
        if let boot = bootTrail(&marks, &ids) { trails.append(boot) }
        for service in model.services.prefix(Self.maxServiceTrails) {
            let steps = service.events.filter { !$0.scopes.isEmpty }.enumerated().map { i, event in
                Trail.Step(n: i + 1, title: "\(event.event) → \(event.reducer)", entries: event.scopes.map { entry($0, cite: nil, event: (service.name, event.event)) })
            }
            guard !steps.isEmpty else { continue }
            var trail = Trail(id: Self.unique(Self.slug(service.name), &ids), mark: Self.mark(service.name, &marks), title: service.name,
                              subtitle: "\(steps.count) event\(steps.count == 1 ? "" : "s")",
                              say: "Each step is an event \(service.name)'s center declares, in its order, and the reducer that answers it.", steps: steps)
            // Each event is sent from elsewhere: its senders are what calls it, not the step before.
            for s in trail.steps.indices { for e in trail.steps[s].entries.indices where s > 0 || e > 0 { trail.steps[s].entries[e].hop = ("sent", 0, 0) } }
            trails.append(trail)
        }
        return trails
    }

    private func bootTrail(_ marks: inout Set<String>, _ ids: inout Set<String>) -> Trail? {
        var start: [Int] = []
        if let entry = model.entry {
            // Where an entry starts: its init, a SwiftUI app's body, a command's main or run; those that call anything.
            let members = graph.scopes.indices.filter { g in
                guard let parent = graph.parentOf(g) else { return false }
                return parent == entry || (graph.scopes[parent].kind == "X" && graph.qualified[parent] == graph.qualified[entry])
            }
            let named = ["init", "body", "main", "run"].compactMap { name in members.first { graph.scopes[$0].name == name } }
            let calling = named.filter { !(outgoing[$0] ?? []).isEmpty }
            start = calling.isEmpty ? Array(named.prefix(1)) : calling
            if start.isEmpty { start = [entry] }
        } else {
            // No entry: the services' boot events, lowest rank last, as a root would send them.
            let boots = model.services.reversed().compactMap { s in s.events.first { $0.event.lowercased().contains("boot") || $0.event.lowercased() == "start" || $0.event.lowercased() == "launch" } }
            start = boots.compactMap(\.scopes.first)
        }
        guard !start.isEmpty else { return nil }
        // When the entry's own code sets off no flow (it hands the app to a root), its sure calls are followed to the
        // first code that does, and that path opens the walk.
        let path = model.entry == nil ? [] : callPath(from: start)
        // Breadth first along the flows, each target in the order its caller's lines send it.
        var order: [[Int]] = start.map { [$0] } + path.map { [$0] }
        var seen = Set(start + path)
        var queue = start + path
        var flowsFound = false
        while let g = queue.first, order.count < 12 {
            queue.removeFirst()
            let next = (outgoing[g] ?? []).filter { $0.via.map(Self.flowKinds.contains) == true }.sorted { ($0.line, $0.target) < ($1.line, $1.target) }
            var byReducer: [Int: [Int]] = [:]
            var groups: [[Int]] = []
            for edge in next where !seen.contains(edge.target) {
                seen.insert(edge.target)
                flowsFound = true
                if let parent = graph.parentOf(edge.target), ["reduce", "effect"].contains(graph.scopes[edge.target].name) {
                    if let at = byReducer[parent] { groups[at[0]].append(edge.target); continue }
                    byReducer[parent] = [groups.count]
                }
                groups.append([edge.target])
            }
            for group in groups where order.count < 12 {
                order.append(group)
                queue.append(contentsOf: group)
            }
        }
        guard flowsFound || model.entry == nil else { return nil }
        let steps = order.enumerated().map { i, group in
            Trail.Step(n: i + 1, title: stepTitle(group[0]), entries: group.map { entry($0, cite: nil) })
        }
        guard steps.count >= 2 else { return nil }
        var trail = Trail(id: Self.unique("boot", &ids), mark: Self.mark("Boot", &marks), title: "Boot",
                          subtitle: model.entry.map { "from \(graph.scopes[$0].name), event by event" } ?? "each service's boot event",
                          say: "How the app starts: its entry, then each event and relay that sets off another, in the order the code sends them.", steps: steps)
        hops(&trail)
        // Each place the app starts from is a start of its own: the system calls it, no entry before it does.
        for s in trail.steps.indices { for e in trail.steps[s].entries.indices where start.contains(trail.steps[s].entries[e].scope) { trail.steps[s].entries[e].hop = nil } }
        return trail
    }

    /// The sure calls from `start` to the nearest declaration that sets off a flow, that declaration last; empty when
    /// one of `start` sets one off itself, or none is found within six calls.
    func callPath(from start: [Int]) -> [Int] {
        let setsOff = { (g: Int) in (outgoing[g] ?? []).contains { $0.via.map(Self.flowKinds.contains) == true } }
        if start.contains(where: setsOff) { return [] }
        var parent: [Int: Int] = [:]
        var depth: [Int: Int] = [:]
        var queue = start
        for g in start { depth[g] = 0 }
        while !queue.isEmpty, depth.count < 2_000 {
            let g = queue.removeFirst()
            guard depth[g]! < 6 else { continue }
            for edge in (outgoing[g] ?? []).sorted(by: { ($0.line, $0.target) < ($1.line, $1.target) }) where edge.tier == 0 && edge.via == nil {
                guard depth[edge.target] == nil else { continue }
                depth[edge.target] = depth[g]! + 1
                parent[edge.target] = g
                if setsOff(edge.target) {
                    var path = [edge.target]
                    var at = g
                    while let up = parent[at] { path.insert(at, at: 0); at = up }
                    return path
                }
                queue.append(edge.target)
            }
        }
        return []
    }

    private func stepTitle(_ g: Int) -> String {
        let scope = graph.scopes[g]
        if ["reduce", "effect"].contains(scope.name), let parent = graph.parentOf(g) { return graph.qualified[parent] }
        return graph.qualified[g] + (scope.isCallable && scope.kind != "i" ? "" : "")
    }

    // MARK: - Entries and hops

    /// An entry for `g`, its note read off the code.
    func entry(_ g: Int, cite: String?, event: (service: String, event: String)? = nil) -> Trail.Entry {
        let scope = graph.scopes[g]
        let file = graph.files[graph.fileOf[g]]
        var note: String
        var cited: String
        let parent = graph.parentOf(g)
        if let doc = file.docText(scope.doc) {
            note = SwiftSource.firstSentence(doc)
            cited = "doc"
        } else if let parent, ["reduce", "effect"].contains(scope.name), let doc = file.docText(graph.scopes[parent].doc) {
            note = SwiftSource.firstSentence(doc)
            cited = "doc"
        } else {
            note = describe(g)
            cited = "code"
        }
        if let event { note = "`\(event.service)`'s `\(event.event)` event: " + note }
        return Trail.Entry(scope: g, id: graph.ids[g], note: note, cite: cite ?? cited, line: scope.sig, hop: nil)
    }

    /// What a declaration does, said from the graph: what it is, where, and the state it writes, the flows and calls
    /// it makes.
    func describe(_ g: Int) -> String {
        let scope = graph.scopes[g]
        let file = graph.files[graph.fileOf[g]]
        let name = graph.qualified[g] + (scope.isCallable ? "(" + scope.labels.map { $0 + ":" }.joined() + ")" : "")
        let lines = (scope.end ?? scope.sig) - scope.decl + 1
        let clauses = CodeFacts(graph: graph).clauses(g, edges: outgoing[g] ?? [])
        return "`\(name)`, \(lines) line\(lines == 1 ? "" : "s") in \((file.path as NSString).lastPathComponent)" + (clauses.isEmpty ? "" : "; it " + clauses.joined(separator: "; it ")) + "."
    }

    /// How each entry after the first is reached: an edge from the latest earlier entry, a sure edge before an
    /// ambiguous one; else a call it makes to the entry before; else none the matcher could read.
    func hops(_ trail: inout Trail) {
        var order: [(scope: Int, step: Int, entry: Int)] = []
        for (s, step) in trail.steps.enumerated() { for (e, entry) in step.entries.enumerated() { order.append((entry.scope, s, e)) } }
        guard order.count > 1 else { return }
        for k in 1..<order.count {
            let b = order[k].scope
            var found: (kind: String, at: Int, tier: Int)?
            for j in stride(from: k - 1, through: 0, by: -1) {
                guard let edge = graph.edge(order[j].scope, b) else { continue }
                if found == nil || (found!.tier == 2 && edge.tier < 2) { found = (edge.via ?? "call", j, edge.tier) }
                if edge.tier < 2 { break }
            }
            if found == nil, let edge = graph.edge(b, order[k - 1].scope) { found = ("caller", k - 1, edge.tier) }
            let at = found?.at ?? k - 1
            trail.steps[order[k].step].entries[order[k].entry].hop = (found?.kind ?? "none", order[at].step + 1, order[at].entry)
        }
    }

    // MARK: - Names

    static func slug(_ text: String) -> String {
        let lowered = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(lowered).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "trail" : joined
    }

    static func unique(_ id: String, _ seen: inout Set<String>) -> String {
        var candidate = id, n = 2
        while seen.contains(candidate) { candidate = "\(id)-\(n)"; n += 1 }
        seen.insert(candidate)
        return candidate
    }

    /// One or two capitals no other trail has: the name's capitals, else its first letters.
    static func mark(_ name: String, _ seen: inout Set<String>) -> String {
        let letters = name.filter(\.isLetter).map { String($0).uppercased() }
        let capitals = name.filter { $0.isUppercase }.map(String.init)
        var candidates: [String] = []
        if capitals.count >= 2 { candidates.append(capitals.prefix(2).joined()) }
        if let first = letters.first { candidates.append(first) }
        for other in letters.dropFirst() { candidates.append((letters.first ?? "T") + other) }
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { candidates.append(String(c)) }
        let mark = candidates.first { !seen.contains($0) } ?? "T"
        seen.insert(mark)
        return mark
    }
}
