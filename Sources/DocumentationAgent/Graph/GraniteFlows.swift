//  WHAT: The Granite flows of a project, read off its declarations: each `GraniteService` and `GraniteComponent`, its
//        center's `@Event`s and the reducer each names, its `@Agent`s, and every name a type or a function holds a
//        service under (`@Relay var`, a parameter, a binding, `Live.service`). A call on one of those is a flow: an
//        event sent to a reducer, a relay to another service or a call on its own, an `@Agent` run; and beside the
//        call sites, an agent's frames, a ticket's reply and a handler the root installed. Ported from Craft's builder.
//  PIN:  RANKED BY RELAYS, NEVER REFUSED FOR THEM. A service's rank is one above the highest service its own code
//        relays to or sends an event to; Craft's build fails on a circle, but this package documents code as it is, so
//        a circle is cut where the walk meets it and said in `cycles`.

import Foundation

final class GraniteFlows {
    struct Host {
        let name: String
        let scope: Int
        let isComponent: Bool
        var events: [(event: String, reducer: String, line: Int)] = []
        var agents: [(name: String, type: String, policy: String, run: Int?, merge: Int?, reduce: [Int])] = []
        var installers: [String: String] = [:]
    }

    struct Handle {
        enum Kind { case service, center, event, agent }
        let kind: Kind
        let host: String
        let member: String?
    }

    struct Context {
        var host: String?
        var handles: [String: String] = [:]
        var locals: [String: Handle] = [:]
    }

    struct Flow { let source: Int; let target: Int; let line: Int; let via: String }

    static let agentRuns: Set<String> = ["perform", "send", "start"]
    private static let eventDecl = Pattern(#"@Event(?:\([^)]*\))?\s+(?:(?:public|package|internal)\s+)*var\s+(\w+)\s*:\s*((?:\w+\.)*\w+)\.Reducer\b"#)
    private static let agentDecl = Pattern(#"@Agent\(((?:[^()]|\([^()]*\))*)\)\s+(?:(?:public|package|internal)\s+)*var\s+(\w+)\s*:\s*(\w+)\.Agent\b"#)
    private static let handleDecl = Pattern(#"\bvar\s+(\w+)\s*:\s*([A-Z]\w*)\b"#)
    private static let param = Pattern(#"\b(\w+)\s*:\s*(?:@\w+\s+)*([A-Z]\w*)\b"#)
    private static let binding = Pattern(#"(?:\blet\b|\bvar\b|,)\s*(\w+)\s*(?::\s*([A-Z]\w*)\s*)?=\s*(?:try\s+)?(?:await\s+)?([\w$\\.]+(?:\([\w$\\.]*\))?[\w$.]*)"#)
    private static let fire = Pattern(#"\b([A-Z]\w*)\.(\w+)\.get\(\s*"root"\s*\)"#)
    private static let putRoot = Pattern(#"\bSelf\.(\w+)\.put\(\s*"root""#)
    private static let liveService = Pattern(#"^Live\.service\((\w+)\.self\)"#)
    private static let executable = Pattern(#"^executable\(\\\.(\w+)\)"#)

    unowned let graph: CallGraph
    private(set) var hosts: [String: Host] = [:]
    private var byQualified: [String: [Int]] = [:]
    /// The services each type holds, by the type's module and qualified name (`handleKey`): `@Relay var account:
    /// AccountService`. Two modules may each have a type of one name; each holds its own.
    private(set) var handles: [String: [String: String]] = [:]

    func handleKey(_ module: Int, _ qualified: String) -> String { "\(module)\u{1}\(qualified)" }
    private var contexts: [Int: Context] = [:]
    /// The folder each service's files live in, when it is named for the service.
    private var serviceFolders: [String: String] = [:]
    /// Circles among the services' relays, each said once, as the walk cut them.
    private(set) var cycles: [String] = []

    var services: [String] { hosts.values.filter { !$0.isComponent }.map(\.name).sorted() }
    var components: [String] { hosts.values.filter(\.isComponent).map(\.name).sorted() }

    init(_ graph: CallGraph) {
        self.graph = graph
        for g in graph.scopes.indices { byQualified[graph.qualified[g], default: []].append(g) }
        // Of two hosts with one name (an app's `Home` and a demo app's), the app's own: in the module the most code
        // shares, outside a demo, an example or a test, in a folder named for it, the shallowest.
        func rank(_ g: Int) -> (Int, Int, Int, String) {
            let path = graph.files[graph.fileOf[g]].path
            let parts = path.split(separator: "/").map(String.init)
            let aside = parts.contains { ["demo", "demos", "example", "examples", "sample", "samples", "tests", "test"].contains($0.lowercased()) }
            let named = parts.dropLast().last == graph.scopes[g].name
            return (aside ? 1 : 0, graph.moduleOf[graph.fileOf[g]] == -1 ? 0 : 1, named ? 0 : 1, String(format: "%03d", parts.count) + path)
        }
        for g in graph.scopes.indices {
            let scope = graph.scopes[g]
            guard scope.kind == "S" || scope.kind == "C", scope.parent < 0 else { continue }
            let file = graph.files[graph.fileOf[g]]
            let line = SwiftText.string(file.blankLine(scope.sig))
            guard let colon = line.firstIndex(of: ":") else { continue }
            let after = line[colon...].prefix { $0 != "{" }
            let conforms = Set(after.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init))
            let isService = conforms.contains("GraniteService"), isComponent = conforms.contains("GraniteComponent")
            guard isService || isComponent else { continue }
            if let known = hosts[scope.name], rank(known.scope) <= rank(g) { continue }
            hosts[scope.name] = Host(name: scope.name, scope: g, isComponent: !isService)
        }
        // A host's events, agents and handles are read only where its code is: its own module, and its own folder
        // when the folder is named for it.
        for (name, host) in hosts {
            let path = graph.files[graph.fileOf[host.scope]].path
            let folder = (path as NSString).deletingLastPathComponent
            hostFolders[name] = (graph.moduleOf[graph.fileOf[host.scope]], (folder as NSString).lastPathComponent == name ? folder + "/" : nil)
        }
        for name in services {
            let path = graph.files[graph.fileOf[hosts[name]!.scope]].path
            let folder = (path as NSString).deletingLastPathComponent
            if (folder as NSString).lastPathComponent == name { serviceFolders[name] = folder + "/" }
        }
        guard !hosts.isEmpty else { return }
        for fi in graph.files.indices {
            let blank = graph.blankStrings[fi], text = graph.textStrings[fi]
            for m in Self.eventDecl.matches(blank) {
                guard let host = owner(fi, m.range.location), let event = m.group(1, in: blank), let reducer = m.group(2, in: blank) else { continue }
                let short = reducer.split(separator: ".").last.map(String.init) ?? reducer
                hosts[host]!.events.append((event, short, graph.files[fi].line(of: m.range.location)))
            }
            for m in Self.agentDecl.matches(blank) {
                guard let host = owner(fi, m.range.location), let policy = m.group(1, in: blank), let name = m.group(2, in: blank),
                      let type = m.group(3, in: blank) else { continue }
                let reduce = [member(type, "reduce", ["state", "event", "run"]), member(type, "reduce", ["state", "lifecycle", "run"])].compactMap { $0 }
                hosts[host]!.agents.append((name, type, policy, member(type, "run", ["_", "context"]),
                                            policy.contains("merge") ? member(type, "merge", ["_", "into", "context"]) : nil, reduce))
            }
            for m in Self.handleDecl.matches(blank) {
                guard let name = m.group(1, in: blank), let type = m.group(2, in: blank), let host = hosts[type], !host.isComponent else { continue }
                let chain = graph.chain(fi, m.range.location)
                guard let inner = chain.first, graph.scopes[inner].isTypeOrExtension else { continue }
                handles[handleKey(graph.moduleOf[fi], graph.qualified[inner]), default: [:]][name] = type
            }
            for m in Self.putRoot.matches(text) {
                guard let registry = m.group(1, in: text), blank.character(at: m.range.location) != SwiftText.space,
                      let host = owner(fi, m.range.location), let inner = graph.chain(fi, m.range.location).first else { continue }
                hosts[host]!.installers[registry] = graph.scopes[inner].name
            }
        }
    }

    func member(_ type: String, _ name: String, _ labels: [String]) -> Int? {
        let hits = graph.typeMembers(type, name).filter { graph.scopes[$0].labels == labels }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Each host's module, and its folder when the folder is named for it.
    private var hostFolders: [String: (module: Int, folder: String?)] = [:]

    /// The host whose type, extension or nested type holds `offset`, in that host's own module and folder.
    func owner(_ fi: Int, _ offset: Int) -> String? {
        for g in graph.chain(fi, offset) {
            let head = String(graph.qualified[g].split(separator: ".").first ?? "")
            guard hosts[head] != nil else { continue }
            if let place = hostFolders[head] {
                if place.module != graph.moduleOf[fi] { return nil }
                if let folder = place.folder, !graph.files[fi].path.hasPrefix(folder) { return nil }
            }
            return head
        }
        return nil
    }

    /// The reduce and the effect of the reducer `host`'s center names for `event`, whichever it has.
    func reducer(_ host: String, _ event: String) -> [Int] {
        guard let name = hosts[host]?.events.first(where: { $0.event == event })?.reducer, let type = reducerType(host, name) else { return [] }
        return ["reduce", "effect"].flatMap { byQualified["\(graph.qualified[type]).\($0)"] ?? [] }
    }

    /// The reducer's own type: declared in the host, its center or an extension of either (`extension
    /// AccountService { struct Boot }`, `extension ContentService.Center { struct Boot }`).
    func reducerType(_ host: String, _ reducer: String) -> Int? {
        let candidates = (graph.types[reducer] ?? []).filter { graph.qualified[$0].hasPrefix(host + ".") }
        return candidates.min { (graph.qualified[$0].count, $0) < (graph.qualified[$1].count, $1) }
    }

    /// What the innermost scope at a call can call a service by: its host, the handles of every type around it, and
    /// the parameters and bindings of every function around it, the outer one first.
    func context(_ chain: [Int]) -> Context {
        let key = chain[0]
        if let known = contexts[key] { return known }
        var ctx = Context()
        for g in chain where graph.scopes[g].isTypeOrExtension {
            let q = graph.qualified[g]
            for (name, service) in handles[handleKey(graph.moduleOf[graph.fileOf[g]], q)] ?? [:] where ctx.handles[name] == nil { ctx.handles[name] = service }
            let head = String(q.split(separator: ".").first ?? "")
            if ctx.host == nil, hosts[head] != nil { ctx.host = head }
        }
        let fi = graph.fileOf[key]
        let blank = graph.blankStrings[fi]
        for g in chain.reversed() {
            let scope = graph.scopes[g]
            guard scope.isCallable, let open = scope.braceOffset, let close = scope.endOffset else { continue }
            for m in Self.param.matches(blank, in: NSRange(location: scope.headOffset, length: open - scope.headOffset)) {
                if let name = m.group(1, in: blank), let type = m.group(2, in: blank), let host = hosts[type], !host.isComponent {
                    ctx.locals[name] = Handle(kind: .service, host: type, member: nil)
                }
            }
            for m in Self.binding.matches(blank, in: NSRange(location: open, length: close - open)) {
                guard let name = m.group(1, in: blank) else { continue }
                if let type = m.group(2, in: blank), let host = hosts[type], !host.isComponent {
                    ctx.locals[name] = Handle(kind: .service, host: type, member: nil)
                } else if let expr = m.group(3, in: blank), let h = handle(expr, ctx) {
                    ctx.locals[name] = h
                }
            }
        }
        contexts[key] = ctx
        return ctx
    }

    /// What an expression holds, if it is one of Granite's handles: a service, its center, an event or an agent.
    func handle(_ raw: String, _ ctx: Context) -> Handle? {
        let expr = raw.replacingOccurrences(of: "?", with: "").replacingOccurrences(of: "!", with: "")
        var head: Handle
        var parts: [String]
        if let m = Self.liveService.first(expr), let name = m.group(1, in: expr) {
            guard let host = hosts[name], !host.isComponent else { return nil }
            head = Handle(kind: .service, host: name, member: nil)
            parts = String(expr[expr.index(expr.startIndex, offsetBy: m.range.length)...]).split(separator: ".").map(String.init)
        } else if let m = Self.executable.first(expr), let name = m.group(1, in: expr) {
            guard let host = ctx.host, hosts[host]?.agents.contains(where: { $0.name == name }) == true else { return nil }
            head = Handle(kind: .agent, host: host, member: name)
            parts = String(expr[expr.index(expr.startIndex, offsetBy: m.range.length)...]).split(separator: ".").map(String.init)
        } else {
            parts = expr.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "self", parts.count > 1, parts[1] != "center" { parts.removeFirst() }
            guard !parts.isEmpty else { return nil }
            let first = parts.removeFirst()
            if let local = ctx.locals[first] { head = local }
            else if let service = ctx.handles[first] { head = Handle(kind: .service, host: service, member: nil) }
            else if let host = ctx.host, ["self", "$0", "service"].contains(first), parts.first == "center" || first == "self" {
                head = Handle(kind: .service, host: host, member: nil)
            } else if let host = ctx.host, first == "center" {
                head = Handle(kind: .center, host: host, member: nil)
            } else {
                return nil
            }
        }
        for part in parts {
            guard let host = hosts[head.host] else { return nil }
            let bare = part.hasPrefix("$") ? String(part.dropFirst()) : part
            if head.kind == .service && part == "center" { head = Handle(kind: .center, host: head.host, member: nil) }
            else if head.kind == .center && host.agents.contains(where: { $0.name == bare }) { head = Handle(kind: .agent, host: head.host, member: bare) }
            else if head.kind == .center && host.events.contains(where: { $0.event == part }) { head = Handle(kind: .event, host: head.host, member: part) }
            else { return nil }
        }
        return head
    }

    /// The expression a call at `offset` is made on, read back from its dot: `$0.center.send`, `account`; nil for a
    /// call with no receiver. A chain broken over lines (`config\n    .center\n    .send(`) reads as one.
    static func receiver(_ blank: [UInt16], _ offset: Int) -> String? {
        typealias T = SwiftText
        var k = offset - 1
        guard k >= 0, blank[k] == T.dot else { return nil }
        k -= 1
        while k >= 0, T.isWhite(blank[k]) { k -= 1 }
        var parts: [ArraySlice<UInt16>] = []
        while k >= 0 {
            let c = blank[k]
            if T.isWord(c) || c == T.underscore || c == T.dollar || c == T.backslash || c == T.question || c == T.bang {
                var a = k
                while a > 0, T.isWord(blank[a - 1]) || blank[a - 1] == T.underscore || blank[a - 1] == T.dollar || blank[a - 1] == T.backslash
                    || blank[a - 1] == T.question || blank[a - 1] == T.bang { a -= 1 }
                parts.append(blank[a...k])
                k = a - 1
            } else if c == T.dot {
                parts.append(blank[k...k])
                k -= 1
                while k >= 0, T.isWhite(blank[k]) { k -= 1 }
            } else if c == T.closeParen {
                var depth = 0, a = k
                while a >= 0 {
                    if blank[a] == T.closeParen { depth += 1 }
                    if blank[a] == T.openParen { depth -= 1 }
                    if depth == 0 { break }
                    a -= 1
                }
                guard a >= 0 else { break }
                parts.append(blank[a...k])
                k = a - 1
            } else if T.isWhite(c), let last = parts.last, last.first == T.dot {
                k -= 1
            } else {
                break
            }
        }
        let text = parts.reversed().map { T.string($0) }.joined()
        let squeezed = text.filter { !$0.isWhitespace }
        return squeezed.isEmpty ? nil : squeezed
    }

    /// The flow a call site makes: `[]` when it is made on a handle but reaches nothing a trail walks (a tap, a
    /// cancel), nil when it is not made on a handle and the match by name decides.
    func flow(_ fi: Int, _ site: CallGraph.Site, _ chain: [Int]) -> [(Int, String?)]? {
        guard !hosts.isEmpty, let expr = Self.receiver(graph.files[fi].blank, site.offset) else { return nil }
        let ctx = context(chain)
        guard let h = handle(expr, ctx) else { return nil }
        switch h.kind {
        case .event:
            return site.name == "send" ? reducer(h.host, h.member ?? "").map { ($0, "event") } : []
        case .agent:
            guard Self.agentRuns.contains(site.name), let agent = hosts[h.host]?.agents.first(where: { $0.name == h.member }) else { return [] }
            return ([agent.run] + (site.name == "send" ? [agent.merge] : [])).compactMap { $0 }.map { ($0, "agent") }
        case .center:
            return []
        case .service:
            let hits = graph.matching(graph.typeMembers(h.host, site.name), site.labels, site.trailing)
            return hits.count == 1 ? [(hits[0], h.host == ctx.host ? "own" : "relay")] : nil
        }
    }

    /// The flows no call site says: the engine reduces every frame an agent's run yields; a facade that waits on a
    /// ticket is woken by the effect it sent the ticket to; a handler the root installed is fired by a service below.
    func after() -> [Flow] {
        var out: [Flow] = []
        for host in hosts.values.sorted(by: { $0.name < $1.name }) {
            for agent in host.agents {
                guard let run = agent.run else { continue }
                out += agent.reduce.map { Flow(source: run, target: $0, line: graph.scopes[$0].sig, via: "frames") }
            }
        }
        func body(_ g: Int) -> NSRange? {
            let scope = graph.scopes[g]
            guard let open = scope.braceOffset, let close = scope.endOffset else { return nil }
            return NSRange(location: open, length: close - open)
        }
        var sent: [Int: [Int]] = [:]
        for edge in graph.edges where edge.via == "event" { sent[edge.source, default: []].append(edge.target) }
        for facade in sent.keys.sorted() {
            guard let range = body(facade), graph.blankStrings[graph.fileOf[facade]].range(of: "tickets.wait(", range: range).location != NSNotFound else { continue }
            for target in sent[facade]! where graph.scopes[target].name == "effect" {
                guard let range = body(target) else { continue }
                let blank = graph.blankStrings[graph.fileOf[target]]
                let at = blank.range(of: #"tickets\.(?:resolve|fail)\("#, options: .regularExpression, range: range)
                guard at.location != NSNotFound else { continue }
                out.append(Flow(source: target, target: facade, line: graph.files[graph.fileOf[target]].line(of: at.location), via: "reply"))
            }
        }
        var installers: [String: (host: String, registry: String)] = [:]
        for host in hosts.values { for (registry, name) in host.installers { installers[name] = (host.name, registry) } }
        guard !installers.isEmpty else { return out }
        var installed: [String: [Int]] = [:]
        let call = Pattern(#"\b(\w+)\.(\w+)[ \t]*\{"#)
        for fi in graph.files.indices {
            let blank = graph.blankStrings[fi]
            for m in call.matches(blank) {
                guard let name = m.group(2, in: blank), let (host, registry) = installers[name] else { continue }
                let open = m.range.location + m.range.length - 1
                let close = SwiftText.closingBrace(graph.files[fi].blank, open)
                for hit in graph.hits[fi] ?? [] where open < hit.offset && hit.offset < close {
                    installed[host + "\u{1}" + registry, default: []] += hit.targets.map(\.scope)
                }
            }
        }
        for fi in graph.files.indices {
            let text = graph.textStrings[fi], blank = graph.blankStrings[fi]
            for m in Self.fire.matches(text) {
                guard blank.character(at: m.range.location) != SwiftText.space, let host = m.group(1, in: text), let registry = m.group(2, in: text),
                      let source = graph.chain(fi, m.range.location).first else { continue }
                for target in installed[host + "\u{1}" + registry] ?? [] {
                    out.append(Flow(source: source, target: target, line: graph.files[fi].line(of: m.range.location), via: "handler"))
                }
            }
        }
        return out
    }

    /// The service a declaration belongs to: the one whose folder holds its file, else the one whose type it sits in.
    func service(of g: Int) -> String? {
        let path = graph.files[graph.fileOf[g]].path
        if let found = serviceFolders.first(where: { path.hasPrefix($0.value) })?.key { return found }
        let head = String(graph.qualified[g].split(separator: ".").first ?? "")
        return hosts[head].map { $0.isComponent ? nil : head } ?? nil
    }

    /// Each service's rank, and the services it reaches: 0 for one that reaches no other, else one above the highest
    /// it relays to or sends an event to. A circle is cut where the walk meets it, and said once in `cycles`.
    func ranks() -> [(name: String, rank: Int, reaches: [String])] {
        var down: [String: Set<String>] = [:]
        for edge in graph.edges where edge.via == "relay" || edge.via == "event" {
            guard let a = service(of: edge.source), let b = service(of: edge.target), a != b else { continue }
            down[a, default: []].insert(b)
        }
        var rank: [String: Int] = [:]
        var path: [String] = []
        var seenCycles: Set<String> = []
        func visit(_ name: String) -> Int {
            if let known = rank[name] { return known }
            path.append(name)
            var best = -1
            for next in (down[name] ?? []).sorted() {
                if let at = path.firstIndex(of: next) {
                    let circle = (path[at...] + [next]).joined(separator: " → ")
                    if seenCycles.insert(Set(path[at...]).sorted().joined(separator: ",")).inserted { cycles.append(circle) }
                    continue
                }
                best = max(best, visit(next))
            }
            path.removeLast()
            rank[name] = best + 1
            return best + 1
        }
        for name in services { _ = visit(name) }
        return services.map { ($0, rank[$0] ?? 0, (down[$0] ?? []).sorted()) }.sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }
}
