//  WHAT: One Swift file, lexed and walked: its declarations in source order (types, extensions, functions, inits,
//        subscripts, computed vars, a protocol's requirements, an enum's cases), its header, its doc comments and its
//        MARKs, and what it says it is in a sentence. Ported from Craft's site builder (`SwiftFile`).
//  PIN:  NEVER FAILS A BUILD. Craft's builder stops on a brace it cannot match; a codebase this package documents is
//        anyone's, with `#if` branches that open a brace twice. A brace with nothing open is passed over, a scope still
//        open at the end closes there, and the file says it was not balanced; a file the lexer cannot read keeps its
//        text and declares nothing.

import Foundation

struct SwiftSource: Sendable {
    /// The `//` block a file opens with, and the lines of its WHAT, IN, OUT and PIN when it has them.
    struct Header: Sendable, Equatable {
        var lines: ClosedRange<Int>
        var what: ClosedRange<Int>?
        var pin: ClosedRange<Int>?
        var input: ClosedRange<Int>?
        var output: ClosedRange<Int>?
    }

    let path: String
    let module: String
    let text: String
    let units: [UInt16]
    let blank: [UInt16]
    let starts: [Int]
    let lines: [String]
    let braces: [SwiftLexer.Brace]
    let doc: Set<Int>
    let marks: [SwiftLexer.Mark]
    /// Why the lexer stopped, when it did.
    let problem: String?
    /// Whether every brace closed one that was open.
    private(set) var balanced = true
    private(set) var header: Header?
    private(set) var scopes: [SwiftScope] = []
    /// The global index of this file's first scope, once a graph has numbered them.
    var first = 0
    private let depths: [Int]

    init(text: String, path: String, module: String) {
        self.path = path
        self.module = module
        self.text = text
        units = SwiftText.units(text)
        starts = SwiftText.lineStarts(units)
        lines = text.components(separatedBy: "\n")
        let lexed = SwiftLexer.lex(units)
        problem = lexed.problem
        blank = lexed.blank
        braces = lexed.problem == nil ? lexed.braces : []
        doc = lexed.doc
        marks = lexed.marks
        var depth = 0
        depths = braces.map { brace in
            depth += brace.open ? 1 : -1
            return depth
        }
        header = readHeader()
        if problem == nil { scopes = walk() }
    }

    func line(of offset: Int) -> Int { SwiftText.line(of: offset, starts: starts) }

    /// The blanked text of line `n`.
    func blankLine(_ n: Int) -> ArraySlice<UInt16> {
        let a = starts[n - 1]
        let b = n < starts.count ? starts[n] - 1 : blank.count
        return blank[a..<max(a, b)]
    }

    /// How many braces are open before `offset`.
    func depth(at offset: Int) -> Int {
        var low = 0, high = braces.count
        while low < high {
            let mid = (low + high) / 2
            if braces[mid].offset < offset { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? 0 : depths[low - 1]
    }

    // MARK: - The header

    private func readHeader() -> Header? {
        var k = 0
        while k < lines.count, lines[k].hasPrefix("//"), !lines[k].hasPrefix("///") { k += 1 }
        guard k > 0 else { return nil }
        var tags: [(line: Int, tag: String)] = []
        for i in 0..<k {
            let body = lines[i].dropFirst(2)
            let trimmed = body.drop { $0 == " " || $0 == "\t" }
            guard trimmed.count < body.count else { continue }
            for tag in ["WHAT", "PIN", "IN", "OUT"] where trimmed.hasPrefix(tag + ":") { tags.append((i + 1, tag)) }
        }
        var header = Header(lines: 1...k)
        for (n, entry) in tags.enumerated() {
            var last = n + 1 < tags.count ? tags[n + 1].line - 1 : k
            while last > entry.line, lines[last - 1].trimmingCharacters(in: .whitespaces) == "//" { last -= 1 }
            let range = entry.line...last
            switch entry.tag {
            case "WHAT": header.what = range
            case "PIN": header.pin = range
            case "IN": header.input = range
            default: header.output = range
            }
        }
        return header
    }

    /// A header part's text, its tag and the comment marks dropped, joined into one paragraph.
    func headerText(_ range: ClosedRange<Int>?) -> String? {
        guard let range else { return nil }
        let joined = lines[(range.lowerBound - 1)..<min(range.upperBound, lines.count)].map { line -> String in
            var body = Substring(line)
            if body.hasPrefix("//") { body = body.dropFirst(2) }
            body = body.drop { $0 == " " || $0 == "\t" }
            for tag in ["WHAT:", "PIN:", "IN:", "OUT:"] where body.hasPrefix(tag) { body = body.dropFirst(tag.count) }
            return body.trimmingCharacters(in: .whitespaces)
        }.joined(separator: " ")
        let text = joined.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// The WHAT of the header, whole.
    var what: String? { headerText(header?.what) }

    /// A doc comment's text: its `///` marks dropped, joined into one paragraph.
    func docText(_ range: ClosedRange<Int>?) -> String? {
        guard let range else { return nil }
        let text = lines[(range.lowerBound - 1)..<min(range.upperBound, lines.count)].map { line -> String in
            var body = line.drop { $0 == " " || $0 == "\t" }
            if body.hasPrefix("///") { body = body.dropFirst(3) }
            return body.trimmingCharacters(in: .whitespaces)
        }.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// The prose of the comment block a file opens with, when it is more than an editor's template (the file's name,
    /// its target, who created it and when, the copyright).
    var leadingProse: String? {
        guard let header, header.what == nil else { return nil }
        let stem = (path as NSString).lastPathComponent
        let bare = (stem as NSString).deletingPathExtension
        let kept = lines[0..<header.lines.upperBound].compactMap { line -> String? in
            let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if body.isEmpty || body == stem || body == bare || body.hasPrefix("Created by") || body.localizedCaseInsensitiveContains("copyright")
                || body.localizedCaseInsensitiveContains("all rights reserved") || body.hasPrefix("swift-tools-version")
                || body.hasPrefix("MARK") || body.hasPrefix("swiftlint") || !body.contains(" ") { return nil }
            return body
        }
        let text = kept.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// What the file is in a sentence: its WHAT, else the doc comment of its first top-level declaration, else the
    /// first doc comment in it, else the prose its opening comment holds; empty when it says nothing.
    var summary: String {
        var text = what
        if text == nil {
            let documented = scopes.first { $0.parent < 0 && $0.doc != nil } ?? scopes.first { $0.doc != nil }
            text = documented.flatMap { docText($0.doc) }
        }
        if text == nil { text = leadingProse }
        return text.map(Self.firstSentence) ?? ""
    }

    /// Up to the first `.`, `!` or `?` followed by a space or the end.
    static func firstSentence(_ text: String) -> String {
        let chars = Array(text)
        for (i, c) in chars.enumerated() where c == "." || c == "!" || c == "?" {
            if i + 1 == chars.count || chars[i + 1].isWhitespace { return String(chars[0...i]) }
        }
        return text
    }

    // MARK: - The walk

    private mutating func walk() -> [SwiftScope] {
        var raw: [SwiftScope] = []
        var stack: [Int?] = []
        var boundary = 0
        for brace in braces {
            let level = brace.depth == 1 && brace.paren == 0 && brace.bracket == 0
            if brace.open {
                if level, let (m, shape) = SwiftDeclaration.find(blank, start: boundary, brace: brace.offset) {
                    let parent = stack.last { $0 != nil }.flatMap { $0 } ?? -1
                    raw.append(SwiftScope(keyword: m.keyword, kind: SwiftScope.kinds[m.keyword] ?? "f", name: shape.name, params: shape.params,
                                          isOperator: shape.isOperator, mods: m.mods, attrs: m.attrs, offset: m.lead,
                                          keywordOffset: m.keywordOffset, parent: parent, braceOffset: brace.offset, braceLine: brace.line,
                                          braceColumn: brace.offset - starts[brace.line - 1], end: nil, endOffset: nil, isRequirement: false))
                    stack.append(raw.count - 1)
                } else {
                    stack.append(nil)
                }
            } else if let top = stack.popLast() {
                if let top {
                    raw[top].end = brace.line
                    raw[top].endOffset = brace.offset
                }
            } else {
                balanced = false
            }
            if level { boundary = brace.offset + 1 }
        }
        if !stack.isEmpty {
            balanced = false
            for case let open? in stack {
                raw[open].end = lines.count
                raw[open].endOffset = blank.count
            }
        }
        requirements(&raw)
        for k in raw.indices {
            var first = line(of: raw[k].offset)
            raw[k].sig = line(of: raw[k].keywordOffset)
            while first > 1, isAttributeLine(blankLine(first - 1)) { first -= 1 }
            raw[k].decl = first
            raw[k].headOffset = starts[first - 1]
        }
        let order = raw.indices.sorted { (raw[$0].decl, raw[$0].keywordOffset) < (raw[$1].decl, raw[$1].keywordOffset) }
        var local: [Int: Int] = [:]
        for (new, old) in order.enumerated() { local[old] = new }
        var scopes = order.map { old -> SwiftScope in
            var scope = raw[old]
            scope.parent = scope.parent >= 0 ? local[scope.parent] ?? -1 : -1
            return scope
        }
        for k in scopes.indices {
            let docLast = scopes[k].decl - 1
            var docFirst = docLast
            while docFirst >= 1, doc.contains(docFirst) { docFirst -= 1 }
            scopes[k].doc = docFirst < docLast ? (docFirst + 1)...docLast : nil
            var flags = 0
            let parent = scopes[k].parent >= 0 ? scopes[scopes[k].parent] : nil
            if scopes[k].isRequirement || parent?.keyword == "protocol" {
                flags |= SwiftScope.requirementFlag
                scopes[k].isRequirement = true
            }
            if scopes[k].isOperator { flags |= SwiftScope.operatorFlag }
            var p = scopes[k].parent
            while p >= 0 {
                if ["f", "i", "d", "s", "v"].contains(scopes[p].kind) {
                    flags |= SwiftScope.localFlag
                    break
                }
                p = scopes[p].parent
            }
            if let braceLine = scopes[k].braceLine, scopes[k].end == braceLine { flags |= SwiftScope.oneLineFlag }
            scopes[k].flags = flags
            if scopes[k].kind == "E" { scopes[k].cases = cases(of: scopes[k]) }
        }
        return scopes
    }

    /// `@Attribute` or `@Attribute(…)` alone on its line.
    private func isAttributeLine(_ line: ArraySlice<UInt16>) -> Bool {
        typealias T = SwiftText
        var p = line.startIndex
        while p < line.endIndex, T.isBlank(line[p]) { p += 1 }
        guard p < line.endIndex, line[p] == T.at else { return false }
        p += 1
        guard p < line.endIndex, T.isIdentStart(line[p]) else { return false }
        while p < line.endIndex, T.isWord(line[p]) { p += 1 }
        if p < line.endIndex, line[p] == T.openParen {
            while p < line.endIndex, line[p] != T.closeParen { p += 1 }
            guard p < line.endIndex else { return false }
            p += 1
        }
        while p < line.endIndex, T.isBlank(line[p]) || line[p] == T.carriage { p += 1 }
        return p == line.endIndex
    }

    /// A protocol's func, init and subscript requirements have no brace of their own: read from its body.
    private func requirements(_ raw: inout [SwiftScope]) {
        typealias T = SwiftText
        let walked = Set(raw.map(\.keywordOffset))
        for p in raw.indices where raw[p].keyword == "protocol" {
            guard let braceOffset = raw[p].braceOffset, let braceLine = raw[p].braceLine, let end = raw[p].end, end > braceLine + 1 else { continue }
            let inner = depth(at: braceOffset + 1)
            for n in (braceLine + 1)..<end {
                let s = starts[n - 1]
                guard depth(at: s) == inner else { continue }
                let lineEnd = n < starts.count ? starts[n] - 1 : blank.count
                guard let m = SwiftDeclaration.match(blank, from: s, end: lineEnd), ["func", "init", "subscript"].contains(m.keyword),
                      !walked.contains(m.keywordOffset) else { continue }
                guard let open = blank[m.end...].firstIndex(of: T.openParen), let close = T.closingParen(blank, open) else { continue }
                let endLine = line(of: close)
                let stop = endLine < starts.count ? starts[endLine] - 1 : blank.count
                guard stop > m.end, let shape = SwiftDeclaration.shape(m.keyword, Array(blank[m.end..<stop])) else { continue }
                raw.append(SwiftScope(keyword: m.keyword, kind: SwiftScope.kinds[m.keyword] ?? "f", name: shape.name, params: shape.params,
                                      isOperator: shape.isOperator, mods: m.mods, attrs: m.attrs, offset: m.lead, keywordOffset: m.keywordOffset,
                                      parent: p, braceOffset: nil, braceLine: nil, braceColumn: nil, end: endLine, endOffset: stop,
                                      isRequirement: true))
            }
        }
    }

    /// An enum's cases: each `case` statement in its body at its own depth, on a line or after a `;`.
    private func cases(of scope: SwiftScope) -> [String] {
        typealias T = SwiftText
        guard let braceOffset = scope.braceOffset, let endOffset = scope.endOffset, endOffset > braceOffset else { return [] }
        let inner = depth(at: braceOffset + 1)
        let caseWord: [UInt16] = Array("case".utf16), indirect: [UInt16] = Array("indirect".utf16)
        var names: [String] = []
        var start = braceOffset + 1
        while start < endOffset {
            var stop = start
            while stop < endOffset, blank[stop] != T.newline, blank[stop] != T.semicolon { stop += 1 }
            let segment = Array(blank[start..<stop])
            var p = T.skipWhite(segment, 0, segment.count)
            if T.has(segment, indirect, at: p), p + indirect.count < segment.count, T.isBlank(segment[p + indirect.count]) {
                p = T.skipBlanks(segment, p + indirect.count, segment.count)
            }
            if T.has(segment, caseWord, at: p), p + 4 < segment.count, T.isWhite(segment[p + 4]), depth(at: start + p) == inner {
                for part in T.splitTop(segment[(p + 5)...], T.comma) {
                    let q = T.skipWhite(part, 0, part.count)
                    if let (name, _) = SwiftDeclaration.identifier(part, q) { names.append(name) }
                }
            }
            start = stop + 1
        }
        return names
    }

    // MARK: - Names

    func qualified(_ k: Int) -> String {
        var names: [String] = []
        var i = k
        while i >= 0 {
            names.append(scopes[i].name)
            i = scopes[i].parent
        }
        return names.reversed().joined(separator: ".")
    }

    /// Stable ids: the file's path, then the qualified name, with the argument labels for callables, and `~2`, `~3`
    /// for a repeat.
    func ids() -> [String] {
        var seen: [String: Int] = [:]
        return scopes.indices.map { k in
            var q = qualified(k)
            if scopes[k].isCallable { q += "(" + scopes[k].labels.map { $0 + ":" }.joined() + ")" }
            else if scopes[k].kind == "X" { q = "extension:" + q }
            let base = path + ":" + q
            seen[base, default: 0] += 1
            return seen[base] == 1 ? base : base + "~\(seen[base]!)"
        }
    }

    /// How many declarations of each kind a plain count of the keywords finds, beside how many the walk found: what the
    /// page's self-check and the tests hold the walk to.
    func keywordCounts() -> (walked: [String: Int], counted: [String: Int]) {
        var walked: [String: Int] = [:]
        for scope in scopes where scope.kind != "v" { walked[scope.kind, default: 0] += 1 }
        var counted: [String: Int] = [:]
        typealias T = SwiftText
        let b = blank
        var i = 0
        while i < b.count {
            guard T.isIdentStart(b[i]), i == 0 || !(T.isWord(b[i - 1]) || b[i - 1] == T.dot) else { i += 1; continue }
            var k = i + 1
            while k < b.count, T.isWord(b[k]) { k += 1 }
            let word = T.string(b[i..<k])
            let next = T.skipWhite(b, k, b.count)
            let nextUnit: UInt16 = next < b.count ? b[next] : 0
            switch word {
            case "func": if k < b.count, T.isWhite(b[k]) { counted["f", default: 0] += 1 }
            case "init":
                var q = next
                if q < b.count, b[q] == T.question || b[q] == T.bang { q = T.skipWhite(b, q + 1, b.count) }
                if q < b.count, b[q] == T.less, let after = SwiftDeclaration.skipAngles(b, q) { q = T.skipWhite(b, after, b.count) }
                if q < b.count, b[q] == T.openParen { counted["i", default: 0] += 1 }
            case "subscript": if nextUnit == T.openParen || nextUnit == T.less { counted["s", default: 0] += 1 }
            case "deinit": counted["d", default: 0] += 1
            case "struct", "enum", "actor", "protocol", "extension", "class":
                if next > k, T.isUpper(nextUnit) || nextUnit == T.underscore || nextUnit == T.backtick {
                    counted[SwiftScope.kinds[word]!, default: 0] += 1
                }
            default: break
            }
            i = k
        }
        return (walked, counted)
    }

    // MARK: - What the page ships

    /// The file as the page's data holds it: its declarations as compact rows, then its text, verbatim.
    func record(first: Int) -> JSONValue {
        let rows: [JSONValue] = scopes.map { scope in
            var row: [JSONValue] = [
                .string(scope.kind), .string(scope.name), scope.isCallable ? .array(scope.labels.map(JSONValue.string)) : .null,
                .string(scope.mods), .int(scope.decl), .int(scope.sig),
                scope.braceLine.map { .array([.int($0), .int(scope.braceColumn ?? 0)]) } ?? .null,
                scope.end.map(JSONValue.int) ?? .null,
                scope.doc.map { .array([.int($0.lowerBound), .int($0.upperBound)]) } ?? .null,
                .int(scope.parent), .int(scope.flags),
            ]
            if scope.kind == "E" { row.append(.array((scope.cases ?? []).map(JSONValue.string))) }
            return .array(row)
        }
        func range(_ r: ClosedRange<Int>?) -> JSONValue { r.map { .array([.int($0.lowerBound), .int($0.upperBound)]) } ?? .null }
        let headerValue: JSONValue = header.map { h in
            .object([("lines", range(h.lines)), ("what", range(h.what)), ("pin", range(h.pin)), ("in", range(h.input)), ("out", range(h.output))])
        } ?? .null
        return .object([
            ("path", .string(path)), ("lines", .int(lineCount)), ("bytes", .int(text.utf8.count)), ("header", headerValue),
            ("summary", .string(summary)), ("marks", .array(marks.map { .array([.int($0.line), .string($0.text)]) })),
            ("first", .int(first)), ("scopes", .array(rows)), ("text", .string(text)),
        ])
    }

    /// Its lines, the last one not counted when the file ends with a newline.
    var lineCount: Int { lines.count - (text.hasSuffix("\n") ? 1 : 0) }
}
