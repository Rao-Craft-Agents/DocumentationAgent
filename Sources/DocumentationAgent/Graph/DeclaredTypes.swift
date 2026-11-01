//  WHAT: What the declarations say a receiver is: stored and computed properties, parameters, `let x: T`, `let x =
//        T(…)`, `x = self.prop`, a function's return type, and who conforms to which protocol. A call on a receiver
//        whose type this can name reaches that type's member exactly, or through a protocol its requirement and every
//        conformer's member. Ported from Craft's site builder (`Typing`), without its pipelines, which are Craft's own.

import Foundation

final class DeclaredTypes {
    private static let propertyTyped = Pattern(#"\b(?:let|var)\s+(\w+)\s*:\s*([^=\n{]+)"#)
    private static let propertyMade = Pattern(#"\b(?:let|var)\s+(\w+)\s*=\s*(?:try\s+|await\s+)*([A-Z]\w*)(?:<[^>\n]*>)?\("#)
    private static let localBound = Pattern(#"(?:\blet\b|\bvar\b|,)\s*(\w+)\s*=\s*((?:try\s+|await\s+)*[\w$.]+(?:\([^\n]*?\))?[\w$.?!]*)"#)
    private static let returns = Pattern(#"\)\s*(?:async\s*)?(?:throws\s*|rethrows\s*)?->\s*([^{]+)"#)
    private static let conformance = Pattern(#"\b(?:struct|class|actor|enum|extension)\s+[\w.]+(?:<[^>{]*>)?\s*:\s*([^{]+)"#)
    private static let refines = Pattern(#"\bprotocol\s+\w+\s*:\s*([^{]+)"#)

    unowned let graph: CallGraph
    /// A type's properties and their types, by the type's simple name.
    private(set) var properties: [String: [String: String]] = [:]
    /// What a callable returns, by its global index.
    private(set) var returnsOf: [Int: String] = [:]
    /// The types that conform to a protocol, by the protocol's name.
    private(set) var conformers: [String: Set<String>] = [:]
    private(set) var protocols: Set<String> = []
    private var locals: [Int: [String: String]] = [:]

    init(_ graph: CallGraph) {
        self.graph = graph
        for g in graph.scopes.indices where graph.scopes[g].kind == "P" { protocols.insert(graph.scopes[g].name) }
        for g in graph.scopes.indices {
            let scope = graph.scopes[g]
            let blank = graph.blankStrings[graph.fileOf[g]]
            let end = scope.braceOffset ?? scope.endOffset ?? scope.headOffset
            guard end > scope.headOffset else { continue }
            let head = NSRange(location: scope.headOffset, length: end - scope.headOffset)
            if scope.isCallable, let m = Self.returns.first(blank, in: head), let text = m.group(1, in: blank), let type = Self.typeName(text) {
                returnsOf[g] = type
            }
            if ["S", "C", "A", "E", "X"].contains(scope.kind), let m = Self.conformance.first(blank, in: head), let list = m.group(1, in: blank) {
                for part in SwiftText.splitTop(Array(list.utf16), SwiftText.comma) {
                    var text = SwiftText.string(part)
                    if let at = text.range(of: #"\bwhere\b"#, options: .regularExpression) { text = String(text[..<at.lowerBound]) }
                    if let type = Self.typeName(text) { conformers[type, default: []].insert(scope.simpleName) }
                }
            }
            if scope.kind == "P", let m = Self.refines.first(blank, in: head), let list = m.group(1, in: blank) {
                for part in SwiftText.splitTop(Array(list.utf16), SwiftText.comma) {
                    if let type = Self.typeName(SwiftText.string(part)) { conformers[type, default: []].insert(scope.name) }
                }
            }
        }
        // A conformer of a protocol that refines another conforms to both.
        for proto in conformers.keys.sorted() {
            for sub in conformers[proto]!.sorted() where protocols.contains(sub) { conformers[proto]!.formUnion(conformers[sub] ?? []) }
        }
        for fi in graph.files.indices {
            let blank = graph.blankStrings[fi]
            for m in Self.propertyTyped.matches(blank) + Self.propertyMade.matches(blank) {
                guard let name = m.group(1, in: blank), let text = m.group(2, in: blank), let inner = graph.chain(fi, m.range.location).first,
                      graph.scopes[inner].isTypeOrExtension, let type = Self.typeName(text) else { continue }
                let owner = graph.scopes[inner].simpleName
                if properties[owner]?[name] == nil { properties[owner, default: [:]][name] = type }
            }
        }
    }

    /// Whether the project declares `name`.
    func declares(_ name: String) -> Bool { graph.types[name] != nil || graph.extensions[name] != nil }

    /// The simple name of the type a declaration's text names, or nil for a closure, a tuple, a collection or nothing:
    /// `(any SessionLoading)?` → `SessionLoading`, `Pipeline<String, Int>` → `Pipeline`, `Hooks.Hook` → `Hook`.
    static func typeName(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            var u = t
            for prefix in ["any ", "some ", "inout "] where u.hasPrefix(prefix) { u = String(u.dropFirst(prefix.count)) }
            if u.hasPrefix("@"), let m = u.range(of: #"^@\w+(?:\([^)]*\))?\s+"#, options: .regularExpression) { u = String(u[m.upperBound...]) }
            u = u.trimmingCharacters(in: .whitespacesAndNewlines)
            if u == t { break }
            t = u
        }
        while let last = t.last, last == "?" || last == "!" || last == " " { t.removeLast() }
        let units = Array(t.utf16)
        let arrow: [UInt16] = Array("->".utf16)
        if units.count >= 2, units.first == SwiftText.openParen, units.last == SwiftText.closeParen {
            let inner = SwiftText.topLevel(units[1..<(units.count - 1)])
            if !SwiftText.contains(inner, arrow) && !inner.contains(SwiftText.comma) { return typeName(String(t.dropFirst().dropLast())) }
        }
        guard let first = units.first, SwiftText.isUpper(first), !SwiftText.contains(SwiftText.topLevel(units), arrow) else { return nil }
        var k = 0
        var parts: [String] = []
        while k < units.count, SwiftText.isUpper(units[k]) {
            var e = k + 1
            while e < units.count, SwiftText.isWord(units[e]) { e += 1 }
            parts.append(SwiftText.string(units[k..<e]))
            guard e + 1 < units.count, units[e] == SwiftText.dot, SwiftText.isUpper(units[e + 1]) else { break }
            k = e + 1
        }
        return parts.last
    }

    /// The names the innermost function at a call can see, with their types: its parameters and its bindings, the
    /// outer function's first.
    func context(_ chain: [Int]) -> [String: String] {
        let key = chain[0]
        if let known = locals[key] { return known }
        var names: [String: String] = [:]
        locals[key] = names
        let types = chain.filter { graph.scopes[$0].isTypeOrExtension }.map { graph.scopes[$0].simpleName }
        let fi = graph.fileOf[key]
        let file = graph.files[fi]
        let blank = graph.blankStrings[fi]
        for g in chain.reversed() {
            let scope = graph.scopes[g]
            guard scope.isCallable, let open = scope.braceOffset, let close = scope.endOffset else { continue }
            if let paren = file.blank[scope.keywordOffset..<open].firstIndex(of: SwiftText.openParen), let shut = SwiftText.closingParen(file.blank, paren), shut < open {
                for fragment in SwiftText.splitTop(file.blank[(paren + 1)..<shut], SwiftText.comma) {
                    guard let k = SwiftText.firstTop(fragment, SwiftText.colon) else { continue }
                    let words = SwiftText.string(fragment[..<k]).split(whereSeparator: \.isWhitespace)
                    if let last = words.last, let type = Self.typeName(SwiftText.string(SwiftText.beforeAssignment(Array(fragment[(k + 1)...])))) {
                        names[last.replacingOccurrences(of: "`", with: "")] = type
                    }
                }
            }
            let range = NSRange(location: open, length: close - open)
            for m in Self.propertyTyped.matches(blank, in: range) {
                if let name = m.group(1, in: blank), let text = m.group(2, in: blank), let type = Self.typeName(text) { names[name] = type }
            }
            for m in Self.localBound.matches(blank, in: range) {
                guard let name = m.group(1, in: blank), names[name] == nil, let expr = m.group(2, in: blank) else { continue }
                if let type = typeOf(expr, chain, names: names, types: types) { names[name] = type }
            }
        }
        locals[key] = names
        return names
    }

    /// The type of `owner.name`, or of what `owner.name(…)` returns.
    func memberType(_ owner: String, _ name: String, call: Bool) -> String? {
        if call { return graph.typeMembers(owner, name).lazy.compactMap { self.returnsOf[$0] }.first }
        if let type = properties[owner]?[name] { return type }
        for proto in conformers.keys.sorted() where conformers[proto]!.contains(owner) {
            if let type = properties[proto]?[name] { return type }
        }
        return nil
    }

    /// The simple name of the type `expr` has, read off the declarations, or nil.
    func typeOf(_ raw: String, _ chain: [Int], names known: [String: String]? = nil, types known2: [String]? = nil) -> String? {
        var expr = raw.trimmingCharacters(in: .whitespaces)
        while let m = expr.range(of: #"^(?:try\s*[?!]?\s+|await\s+)"#, options: .regularExpression) { expr = String(expr[m.upperBound...]) }
        let u = Array(expr.utf16)
        var parts: [(word: String, call: Bool)] = []
        var k = 0
        while k < u.count {
            var e = k
            if e < u.count, u[e] == SwiftText.dollar { e += 1 }
            while e < u.count, SwiftText.isWord(u[e]) { e += 1 }
            guard e > k else { return nil }
            let word = SwiftText.string(u[k..<e])
            k = e
            let call = k < u.count && u[k] == SwiftText.openParen
            if call {
                guard let close = SwiftText.closingParen(u, k) else { return nil }
                k = close + 1
            }
            while k < u.count, u[k] == SwiftText.question || u[k] == SwiftText.bang { k += 1 }
            parts.append((word, call))
            if k < u.count {
                guard u[k] == SwiftText.dot else { return nil }
                k += 1
            }
        }
        guard let (head, call) = parts.first else { return nil }
        let names = known ?? context(chain)
        let types = known2 ?? chain.filter { graph.scopes[$0].isTypeOrExtension }.map { graph.scopes[$0].simpleName }
        var rest = Array(parts.dropFirst())
        var current: String?
        if head == "self" && !call {
            current = types.first
        } else if let first = head.utf16.first, SwiftText.isUpper(first) {
            if call {
                current = declares(head) ? head : nil
            } else if let next = rest.first {
                current = declares(head) ? memberType(head, next.word, call: next.call) : nil
                rest.removeFirst()
            }
        } else if let type = names[head], !call {
            current = type
        } else if call {
            current = types.lazy.flatMap { self.graph.typeMembers($0, head) }.compactMap { self.returnsOf[$0] }.first
            if current == nil { current = (graph.globals[head] ?? []).lazy.compactMap { self.returnsOf[$0] }.first }
        } else {
            current = types.lazy.compactMap { self.properties[$0]?[head] }.first
        }
        for part in rest {
            guard let type = current else { return nil }
            current = memberType(type, part.word, call: part.call)
        }
        return current
    }

    /// The edges a call on a typed receiver makes: `[]` when the receiver is a type the project does not declare, nil
    /// when its type cannot be read and the match by name decides.
    func call(_ fi: Int, _ site: CallGraph.Site, _ chain: [Int]) -> [(Int, String?)]? {
        guard !CallGraph.keywords.contains(site.name), let expr = GraniteFlows.receiver(graph.files[fi].blank, site.offset),
              let type = typeOf(expr, chain) else { return nil }
        guard declares(type) else { return [] }
        if protocols.contains(type) {
            var hits = (conformers[type] ?? []).sorted().flatMap { graph.matching(graph.typeMembers($0, site.name), site.labels, site.trailing) }
            hits += graph.matching(graph.typeMembers(type, site.name), site.labels, site.trailing)
            return hits.isEmpty ? nil : hits.map { ($0, "protocol") }
        }
        let hits = graph.matching(graph.typeMembers(type, site.name), site.labels, site.trailing)
        return hits.count == 1 ? [(hits[0], nil)] : nil
    }
}
