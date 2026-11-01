//  WHAT: The static call graph of a project's Swift: every call site in every function, matched to the declarations
//        it can reach by name and argument labels, each edge saying how sure the match is, and the Granite flows and
//        the calls through declared types read beside it. Ported from Craft's site builder (`Graph`).
//  PIN:  MATCHED, NOT COMPILED. Exact: one declaration fits and its type is named or implied. Likely: the name and
//        labels are unique and the receiver's type was not read. Ambiguous: two to eight fit, and all are listed. A
//        call on a receiver whose type the declarations name reaches that type's member, and a call on a type the
//        project does not declare (a `String`, a closure) makes no edge, so a common name never fans out to the code.

import Foundation

final class CallGraph {
    struct Edge: Sendable {
        let source: Int
        let target: Int
        var tier: Int
        let line: Int
        var count: Int
        var via: String?
    }

    struct Target: Sendable {
        let scope: Int
        let tier: Int
        let via: String?
    }

    enum SiteKind { case call, chained, implicit }

    struct Site {
        let offset: Int
        let line: Int
        let quals: [String]
        let name: String
        let kind: SiteKind
        let labels: [String]
        let trailing: Bool
    }

    private struct EdgeKey: Hashable { let source: Int; let target: Int }

    static let tiers = ["exact", "likely", "ambiguous"]
    static let fanout = 8

    /// Names that are also methods on the Swift, Foundation and SwiftUI types code calls all the time: a call through a
    /// value receiver or an implicit member never resolves to the project's declaration of the same name.
    static let shadowed: Set<String> = Set("""
        append contains prefix suffix map filter reduce compactMap flatMap forEach first last min max sum sorted sort insert remove \
        removeAll removeFirst removeLast popLast index firstIndex lastIndex count encode decode write read print split joined hash \
        data flush replacing replacingOccurrences trimmingCharacters components starts hasPrefix hasSuffix lowercased uppercased \
        reversed enumerated zip stride range dropFirst dropLast drop element merge reserveCapacity yield finish cancel resume value \
        values keys update updateValue removeValue union intersection subtracting formUnion isEmpty description padding frame \
        foregroundStyle foregroundColor font background overlay onAppear onDisappear onChange task sheet padding lock unlock withLock \
        offset opacity shadow cornerRadius clipShape animation transition environment environmentObject tag id
        """.split(separator: " ").map(String.init))
    /// Words that never name a call.
    static let keywords: Set<String> = Set("""
        if guard while for switch return throw throws rethrows try await async in where case default else defer repeat do catch as \
        is let var func init deinit subscript super self Self get set willSet didSet some any inout typealias associatedtype import \
        struct class enum extension protocol actor static public private internal fileprivate package true false nil break continue \
        fallthrough consume copy
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
    static let control: Set<String> = ["if", "guard", "while", "for", "switch", "else", "catch", "case", "repeat"]
    static let accessors: Set<String> = ["set", "get"]

    let files: [SwiftSource]
    /// Every declaration of every file, numbered across the project: its file, its index there, the scope itself, its
    /// qualified name and its id.
    private(set) var fileOf: [Int] = []
    private(set) var localOf: [Int] = []
    private(set) var scopes: [SwiftScope] = []
    private(set) var qualified: [String] = []
    private(set) var ids: [String] = []
    private(set) var blankStrings: [NSString] = []
    private(set) var textStrings: [NSString] = []

    private(set) var types: [String: [Int]] = [:]
    private(set) var extensions: [String: [Int]] = [:]
    private(set) var members: [String: [Int]] = [:]
    private(set) var byName: [String: [Int]] = [:]
    private(set) var globals: [String: [Int]] = [:]
    private(set) var enumsWithCase: [String: [Int]] = [:]
    private var inits: [String: [Int]] = [:]
    private var localFunctions: [String: [Int]] = [:]
    /// Each file's scopes that have a body, for finding what holds an offset.
    private var bodies: [[Int]] = []
    /// Each file's module, as a number: the package target, else the local package, else the app it belongs to. Of
    /// several declarations a name fits, the caller's own module's are preferred, as Swift's lookup prefers them.
    private(set) var moduleOf: [Int] = []

    private var edgeIndex: [EdgeKey: Int] = [:]
    private(set) var edges: [Edge] = []
    private(set) var unresolved: [String: Int] = [:]
    private(set) var likelyNames: [String: Int] = [:]
    /// The targets each call site reached, by file: what a root handler's closure is read from.
    private(set) var hits: [Int: [(offset: Int, targets: [Target])]] = [:]
    private(set) var granite: GraniteFlows!
    private(set) var typing: DeclaredTypes!

    /// `modules`: the folders (from the project's root, ending in `/`) that hold a module of their own.
    init(_ files: [SwiftSource], modules: [String] = []) {
        var numbered = files
        let prefixes = modules.sorted { $0.count > $1.count }
        moduleOf = files.map { file in (prefixes.firstIndex { file.path.hasPrefix($0) } ?? -1) }
        for fi in numbered.indices {
            numbered[fi].first = scopes.count
            let source = numbered[fi]
            let fileIDs = source.ids()
            var withBody: [Int] = []
            for k in source.scopes.indices {
                let g = scopes.count
                fileOf.append(fi)
                localOf.append(k)
                scopes.append(source.scopes[k])
                qualified.append(source.qualified(k))
                ids.append(fileIDs[k])
                if source.scopes[k].braceOffset != nil { withBody.append(g) }
            }
            bodies.append(withBody)
            blankStrings.append(NSString(characters: source.blank, length: source.blank.count))
            textStrings.append(NSString(characters: source.units, length: source.units.count))
        }
        self.files = numbered
        for g in scopes.indices {
            let scope = scopes[g]
            let simple = scope.simpleName
            if scope.isType { types[simple, default: []].append(g) }
            if scope.kind == "X" { extensions[simple, default: []].append(g) }
            for name in scope.cases ?? [] { enumsWithCase[name, default: []].append(g) }
        }
        for g in scopes.indices where scopes[g].isCallable {
            let scope = scopes[g]
            let parent = parentOf(g)
            if let parent, scopes[parent].isTypeOrExtension { members[Self.memberKey(scopes[parent].simpleName, scope.name), default: []].append(g) }
            if scope.kind != "i" && scope.flags & SwiftScope.localFlag == 0 { byName[scope.name, default: []].append(g) }
            if scope.kind == "f" && parent == nil { globals[scope.name, default: []].append(g) }
            if scope.kind == "i", let parent { inits[qualified[parent], default: []].append(g) }
            if scope.kind == "f" && scope.flags & SwiftScope.localFlag != 0 { localFunctions[scope.name, default: []].append(g) }
        }
    }

    static func memberKey(_ type: String, _ name: String) -> String { type + "\u{1}" + name }

    func parentOf(_ g: Int) -> Int? {
        let p = scopes[g].parent
        return p >= 0 ? g - localOf[g] + p : nil
    }

    func typeMembers(_ type: String, _ name: String) -> [Int] { members[Self.memberKey(type, name)] ?? [] }

    func parentName(_ g: Int) -> String? { parentOf(g).map { scopes[$0].simpleName } }

    // MARK: - Matching

    static func accepts(_ params: [SwiftDeclaration.Param], _ labels: [String], _ trailing: Bool) -> Bool {
        var i = 0, j = 0
        let n = params.count
        while i < n && j < labels.count {
            let p = params[i]
            if labels[j] == p.label {
                i += 1
                j += 1
                while p.isVariadic && j < labels.count && labels[j] == "_" { j += 1 }
            } else if p.hasDefault {
                i += 1
            } else {
                return false
            }
        }
        if j < labels.count { return false }
        if trailing {
            while i < n && !params[i].isClosure {
                if !params[i].hasDefault { return false }
                i += 1
            }
            if i >= n { return false }
            i += 1
        }
        return params[i...].allSatisfy(\.hasDefault)
    }

    func matching(_ candidates: [Int], _ labels: [String], _ trailing: Bool) -> [Int] {
        candidates.filter { Self.accepts(scopes[$0].params, labels, trailing) }
    }

    /// Of several declarations, the ones in the module of file `fi`, when that narrows them and leaves any.
    func local(_ hits: [Int], _ fi: Int) -> [Int] {
        guard hits.count > 1 else { return hits }
        let mine = hits.filter { moduleOf[fileOf[$0]] == moduleOf[fi] }
        return mine.isEmpty ? hits : mine
    }

    /// The named scopes around `offset` in file `fi`, innermost first.
    func chain(_ fi: Int, _ offset: Int) -> [Int] {
        var inner: Int?
        for g in bodies[fi] {
            let scope = scopes[g]
            guard let open = scope.braceOffset, let close = scope.endOffset, open < offset, offset <= close else { continue }
            if inner == nil || open > scopes[inner!].braceOffset! { inner = g }
        }
        var out: [Int] = []
        var at = inner
        while let g = at {
            out.append(g)
            at = parentOf(g)
        }
        return out
    }

    /// The types `name` reaches from inside `chain`: every top-level one, and a nested one only from inside the type it
    /// is nested in, as Swift's lookup reads it; a bare `Set(…)` is the standard library's, not a nested `Set`.
    func visibleTypes(_ name: String, _ chain: [Int]) -> [Int] {
        let around = Set(chain.filter { scopes[$0].isTypeOrExtension }.map { scopes[$0].simpleName })
        return (types[name] ?? []).filter { g in
            guard let parent = parentOf(g) else { return true }
            return around.contains(scopes[parent].simpleName)
        }
    }

    /// `Name(…)`: an init of the type the name reaches, or `owner.Name(…)` one nested in `owner`.
    func construct(_ name: String, _ labels: [String], _ trailing: Bool, chain: [Int]? = nil, owner: String? = nil, from fi: Int) -> [(Int, Int)] {
        var found: [Int]
        if let owner { found = (types[name] ?? []).filter { parentName($0) == owner } }
        else if let chain { found = visibleTypes(name, chain) }
        else { found = types[name] ?? [] }
        guard !found.isEmpty else { return [] }
        found = local(found, fi)
        // Two modules' types may share a qualified name, and so their inits a key: narrowed again.
        let candidates = Array(Set(found.flatMap { inits[qualified[$0]] ?? [] })).sorted()
        let hits = local(matching(candidates, labels, trailing), fi)
        if hits.count == 1 { return [(hits[0], 0)] }
        if hits.count > 1 { return hits.prefix(Self.fanout).map { ($0, 2) } }
        return found.count == 1 ? [(found[0], 0)] : found.prefix(Self.fanout).map { ($0, 2) }
    }

    func unqualified(_ chain: [Int], _ name: String, _ labels: [String], _ trailing: Bool, from fi: Int) -> [(Int, Int)] {
        for a in chain {
            let local = (localFunctions[name] ?? []).filter { parentOf($0) == a }
            let hits = matching(local, labels, trailing)
            if hits.count == 1 { return [(hits[0], 0)] }
        }
        for a in chain where scopes[a].isTypeOrExtension {
            let hits = matching(typeMembers(scopes[a].simpleName, name), labels, trailing)
            if hits.count == 1 { return [(hits[0], 0)] }
            if hits.count > 1 && hits.count <= Self.fanout { return hits.map { ($0, 2) } }
        }
        let hits = local(matching(globals[name] ?? [], labels, trailing), fi)
        if hits.count == 1 { return [(hits[0], 0)] }
        return hits.count > 1 && hits.count <= Self.fanout ? hits.map { ($0, 2) } : []
    }

    func receiver(_ name: String, _ labels: [String], _ trailing: Bool, from fi: Int) -> [(Int, Int)] {
        guard !Self.shadowed.contains(name) else { return [] }
        let hits = local(matching(byName[name] ?? [], labels, trailing), fi)
        if hits.count == 1 {
            likelyNames[name, default: 0] += 1
            return [(hits[0], 1)]
        }
        return hits.count > 1 && hits.count <= Self.fanout ? hits.map { ($0, 2) } : []
    }

    /// `.name(…)` with no receiver: a static func or an enum case of a type the matcher never sees. A case is matched
    /// by its name alone, so it makes an edge only when one enum in the project has it.
    func implicit(_ name: String, _ labels: [String], _ trailing: Bool, from fi: Int) -> [(Int, Int)] {
        guard !Self.shadowed.contains(name) else { return [] }
        let funcs = local(matching(byName[name] ?? [], labels, trailing).filter { scopes[$0].mods.split(separator: " ").contains("static") }, fi)
        let enums = local(enumsWithCase[name] ?? [], fi)
        let hits = funcs + (enums.count == 1 ? enums : [])
        if hits.count == 1 {
            likelyNames[name, default: 0] += 1
            return [(hits[0], 1)]
        }
        return hits.count > 1 && hits.count <= Self.fanout ? hits.map { ($0, 2) } : []
    }

    func resolve(_ fi: Int, _ site: Site) -> (chain: [Int], targets: [(Int, Int)]) {
        let chain = self.chain(fi, site.offset)
        let name = site.name, labels = site.labels, trailing = site.trailing
        switch site.kind {
        case .implicit: return (chain, implicit(name, labels, trailing, from: fi))
        case .chained: return (chain, receiver(name, labels, trailing, from: fi))
        case .call: break
        }
        let quals = site.quals
        guard let head = quals.first, let last = quals.last else {
            if let first = name.utf16.first, SwiftText.isUpper(first) { return (chain, construct(name, labels, trailing, chain: chain, from: fi)) }
            return (chain, unqualified(chain, name, labels, trailing, from: fi))
        }
        if head == "super" { return (chain, []) }
        if quals == ["self"] || quals == ["Self"] { return (chain, unqualified(chain.filter { scopes[$0].isTypeOrExtension }, name, labels, trailing, from: fi)) }
        if let first = last.utf16.first, SwiftText.isUpper(first) {
            guard types[last] != nil || extensions[last] != nil else { return (chain, []) }
            if let n = name.utf16.first, SwiftText.isUpper(n) { return (chain, construct(name, labels, trailing, owner: last, from: fi)) }
            let candidates = local(typeMembers(last, name), fi)
            let hits = matching(candidates, labels, trailing)
            if hits.count == 1 { return (chain, [(hits[0], 0)]) }
            if !hits.isEmpty { return (chain, hits.prefix(Self.fanout).map { ($0, 2) }) }
            if let e = (enumsWithCase[name] ?? []).first(where: { scopes[$0].simpleName == last }) { return (chain, [(e, 0)]) }
            return (chain, candidates.count == 1 ? [(candidates[0], 1)] : [])
        }
        return (chain, receiver(name, labels, trailing, from: fi))
    }

    // MARK: - Sites

    /// The labels of the call whose `(` is at `open`, whether a trailing closure follows its `)`, and where that is.
    func callLabels(_ fi: Int, _ open: Int) -> (labels: [String], trailing: Bool) {
        typealias T = SwiftText
        let f = files[fi]
        let blank = f.blank
        guard let close = T.closingParen(blank, open) else { return ([], false) }
        var labels: [String] = []
        if !T.trimmed(Array(f.units[(open + 1)..<close])).isEmpty {
            for argument in T.splitTop(blank[(open + 1)..<close], T.comma) {
                let p = T.skipWhite(argument, 0, argument.count)
                if let (word, after) = T.word(argument, at: p) {
                    let q = T.skipWhite(argument, after, argument.count)
                    if q < argument.count, argument[q] == T.colon, !(q + 1 < argument.count && argument[q + 1] == T.colon) {
                        labels.append(word)
                        continue
                    }
                }
                labels.append("_")
            }
        }
        let q = T.skipBlanks(blank, close + 1, min(blank.count, close + 41))
        return (labels, q < blank.count && blank[q] == T.openBrace)
    }

    /// Every call site of file `fi`: `name(`, `a.b.name(`, `Name {`, then `.name(` made on a value or with no receiver.
    func sites(_ fi: Int) -> [Site] {
        typealias T = SwiftText
        let f = files[fi]
        let b = f.blank
        let n = b.count
        let heads = f.scopes.map { ($0.headOffset, $0.braceOffset ?? $0.endOffset ?? $0.headOffset) }.sorted { $0.0 < $1.0 }
        let headStarts = heads.map(\.0)
        func inHead(_ offset: Int) -> Bool {
            var low = 0, high = headStarts.count
            while low < high {
                let mid = (low + high) / 2
                if headStarts[mid] <= offset { low = mid + 1 } else { high = mid }
            }
            let k = low - 1
            return k >= 0 && heads[k].0 <= offset && offset < heads[k].1
        }
        func lineInfo(_ offset: Int) -> (line: Int, first: String, colon: Int?) {
            let line = f.line(of: offset)
            let a = f.starts[line - 1], e = line < f.starts.count ? f.starts[line] - 1 : n
            var p = T.skipWhite(b, a, e)
            if p < e, b[p] == T.closeBrace { p = T.skipWhite(b, p + 1, e) }
            let first = T.word(b, at: p, end: e)?.0 ?? ""
            guard first == "case" else { return (line, first, nil) }
            var depth = 0
            for k in a..<e {
                let c = b[k]
                if c == T.openParen || c == T.openBracket || c == T.openBrace { depth += 1 }
                else if c == T.closeParen || c == T.closeBracket || c == T.closeBrace { depth -= 1 }
                else if c == T.colon && depth == 0 { return (line, first, k) }
            }
            return (line, first, line < f.starts.count ? f.starts[line] : n)
        }
        // `#if os(iOS)`, `#available(…)`: a compiler directive's parentheses are no call.
        func isDirective(_ line: Int) -> Bool {
            let a = f.starts[line - 1], e = line < f.starts.count ? f.starts[line] - 1 : n
            let p = T.skipBlanks(b, a, e)
            return p < e && b[p] == T.hash
        }
        var out: [Site] = []
        var named: Set<Int> = []
        var i = 0
        while i < n {
            let c = b[i]
            guard T.isIdentStart(c) else { i += 1; continue }
            if i > 0 {
                let p = b[i - 1]
                if T.isWord(p) || p == T.at || p == T.hash || p == T.dot || p == T.backslash || p == T.dollar { i += 1; continue }
            }
            // A chain of `word[?!]?.` qualifiers, then the name, then blanks, then `(` or `{`.
            var words: [(start: Int, text: String)] = []
            var k = i
            var matched: (name: Int, open: Int)?
            while true {
                guard k < n, T.isIdentStart(b[k]) else { break }
                let start = k
                k += 1
                while k < n, T.isWord(b[k]) { k += 1 }
                words.append((start, T.string(b[start..<k])))
                var q = k
                if q < n, b[q] == T.question || b[q] == T.bang { q += 1 }
                if q + 1 < n, b[q] == T.dot, T.isIdentStart(b[q + 1]) {
                    k = q + 1
                    continue
                }
                let open = T.skipBlanks(b, k, n)
                if open < n, b[open] == T.openParen || b[open] == T.openBrace { matched = (start, open) }
                break
            }
            guard let (nameStart, open) = matched else {
                i = k > i ? k : i + 1
                continue
            }
            let name = words[words.count - 1].text
            let quals = words.dropLast().map { $0.text }
            named.insert(nameStart)
            i = open + 1
            let isAccessorCall: Bool = {
                guard Self.accessors.contains(name), b[open] == T.openParen else { return false }
                if !quals.isEmpty { return true }
                guard let close = T.closingParen(b, open) else { return false }
                let q = T.skipWhite(b, close + 1, min(n, close + 41))
                return !(q < n && b[q] == T.openBrace)
            }()
            if (Self.keywords.contains(name) && !isAccessorCall) || quals.first == "super" || inHead(words[0].start) { continue }
            let info = lineInfo(nameStart)
            if let colon = info.colon, nameStart < colon { continue }
            if isDirective(info.line) { continue }
            if b[open] == T.openBrace {
                let before = T.trimmed(Array(b[f.starts[info.line - 1]..<words[0].start]))
                let upper = SwiftText.isUpper(name.utf16.first ?? 0)
                guard upper || !quals.isEmpty else { continue }
                if !before.isEmpty && !Self.opensAnExpression(T.string(before)) { continue }
                out.append(Site(offset: nameStart, line: info.line, quals: quals, name: name, kind: .call, labels: [], trailing: true))
            } else {
                var (labels, trailing) = callLabels(fi, open)
                if trailing && Self.control.contains(info.first) { trailing = false }
                out.append(Site(offset: nameStart, line: info.line, quals: quals, name: name, kind: .call, labels: labels, trailing: trailing))
            }
        }
        // `.name(`: made on a value (`x.name(`, `f().name(`), or implicit (`.name(` with no receiver).
        i = 0
        while i < n {
            guard b[i] == T.dot, i + 1 < n, T.isIdentStart(b[i + 1]) else { i += 1; continue }
            let start = i + 1
            var k = start + 1
            while k < n, T.isWord(b[k]) { k += 1 }
            let open = T.skipBlanks(b, k, n)
            guard open < n, b[open] == T.openParen else { i = k; continue }
            i = open + 1
            let name = T.string(b[start..<k])
            if named.contains(start) || (Self.keywords.contains(name) && !Self.accessors.contains(name)) || inHead(start - 1) { continue }
            let info = lineInfo(start)
            if let colon = info.colon, start < colon { continue }
            if isDirective(info.line) { continue }
            var p = start - 2
            while p >= 0, b[p] == T.space || b[p] == T.tab || b[p] == T.newline { p -= 1 }
            let prev: UInt16 = p >= 0 ? b[p] : 0
            if T.isDigit(prev) { continue }
            let chained = T.isWord(prev) || prev == T.closeParen || prev == T.closeBracket || prev == T.question || prev == T.bang
                || prev == T.dollar
            var (labels, trailing) = callLabels(fi, open)
            if trailing && Self.control.contains(info.first) { trailing = false }
            out.append(Site(offset: start, line: info.line, quals: [], name: name, kind: chained ? .chained : .implicit, labels: labels, trailing: trailing))
        }
        return out
    }

    /// Whether a line that runs up to `Name {` leaves an expression open there: after `=`, `(`, `,`, `:`, `[`, or the
    /// words `return`, `try`, `await`.
    static func opensAnExpression(_ tail: String) -> Bool {
        if ["=", "(", ",", ":", "["].contains(where: { tail.hasSuffix($0) }) { return true }
        for word in ["return", "try", "await"] where tail.hasSuffix(word) {
            let cut = tail.dropLast(word.count)
            guard let last = cut.last else { return true }
            if !(last.isLetter || last.isNumber || last == "_") { return true }
        }
        return false
    }

    // MARK: - Building

    func add(_ source: Int, _ target: Int, tier: Int, line: Int, via: String?) {
        let key = EdgeKey(source: source, target: target)
        if let at = edgeIndex[key] {
            edges[at].tier = min(edges[at].tier, tier)
            edges[at].count += 1
            if let via, edges[at].via == nil { edges[at].via = via }
        } else {
            edgeIndex[key] = edges.count
            edges.append(Edge(source: source, target: target, tier: tier, line: line, count: 1, via: via))
        }
    }

    /// Every call site of every file resolved: the Granite flow it makes, else the declared type's member it reaches,
    /// else what its name and labels match. Then the flows no call site says: an agent's frames, a ticket's reply, a
    /// handler the root installed. The edges, sorted by caller, line and callee.
    func build() {
        let declared = Set(byName.keys).union(types.keys).union(["init"])
        granite = GraniteFlows(self)
        typing = DeclaredTypes(self)
        for fi in files.indices {
            for site in sites(fi) {
                let (chain, matched) = resolve(fi, site)
                guard let caller = chain.first else { continue }
                var flows = granite.flow(fi, site, chain)
                if flows == nil { flows = typing.call(fi, site, chain) }
                let targets: [Target] = flows.map { $0.map { Target(scope: $0.0, tier: 0, via: $0.1) } }
                    ?? matched.map { Target(scope: $0.0, tier: $0.1, via: nil) }
                if targets.isEmpty {
                    if flows == nil, declared.contains(site.name), !Self.shadowed.contains(site.name) { unresolved[site.name, default: 0] += 1 }
                    continue
                }
                hits[fi, default: []].append((site.offset, targets))
                for target in targets { add(caller, target.scope, tier: target.tier, line: site.line, via: target.via) }
            }
        }
        for flow in granite.after() { add(flow.source, flow.target, tier: 0, line: flow.line, via: flow.via) }
        edges.sort { ($0.source, $0.line, $0.target) < ($1.source, $1.line, $1.target) }
        edgeIndex = [:]
        for (i, edge) in edges.enumerated() { edgeIndex[EdgeKey(source: edge.source, target: edge.target)] = i }
    }

    /// The edge from `source` to `target`, if the graph has one.
    func edge(_ source: Int, _ target: Int) -> Edge? { edgeIndex[EdgeKey(source: source, target: target)].map { edges[$0] } }
}
