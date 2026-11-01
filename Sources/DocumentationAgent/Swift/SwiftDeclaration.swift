//  WHAT: What a line that opens a declaration says, read off the blanked text: its attributes, its modifiers, its
//        keyword, and from what follows the keyword up to its brace, its name and its parameters, each with its label
//        and whether it has a default, takes a closure or is variadic. Ported from Craft's site builder.
//  PIN:  THE LAST DECLARING LINE BEFORE A BRACE DECIDES. Read backwards from a brace over the text since the last brace
//        at its level, the last line (or `;` statement) that opens with a declaration keyword either is the brace's
//        declaration, or the brace is a block: a closure, a `didSet`, a `let`'s initializer.

import Foundation

enum SwiftDeclaration {
    /// One parameter: its label (`_` when it has none), and how a call may leave it out.
    struct Param: Sendable, Equatable {
        let label: String
        let hasDefault: Bool
        let isClosure: Bool
        let isVariadic: Bool
    }

    /// A declaring line, matched.
    struct Match: Sendable {
        /// Where the declaration starts: its first attribute, modifier or keyword.
        let lead: Int
        let attrs: [String]
        let mods: String
        let keyword: String
        let keywordOffset: Int
        /// Just after the keyword.
        let end: Int
    }

    /// What follows a keyword, read: the name and the parameters.
    struct Shape: Sendable {
        let name: String
        let params: [Param]
        let isOperator: Bool
    }

    static let keywords: Set<String> = ["func", "init", "deinit", "subscript", "var", "let", "struct", "class", "enum", "actor",
                                        "extension", "protocol"]
    static let modifiers: Set<String> = ["public", "private", "fileprivate", "internal", "open", "package", "static", "class", "final",
                                         "mutating", "nonmutating", "override", "nonisolated", "lazy", "weak", "unowned", "indirect",
                                         "convenience", "required", "dynamic", "optional", "isolated", "consuming", "borrowing",
                                         "prefix", "postfix", "infix", "distributed", "nonisolated(unsafe)"]
    private static let operatorUnits: Set<UInt16> = Set("-+*/<>=!%&|^~?.".utf16)

    /// The declaring line at `from` in `s` (before `end`), as Craft's `DECL` reads it: blanks, `@attributes` each
    /// followed by a blank on the same line, modifiers, then a keyword not followed by a letter.
    static func match(_ s: [UInt16], from: Int, end: Int) -> Match? {
        typealias T = SwiftText
        var p = T.skipBlanks(s, from, end)
        let lead = p
        var attrs: [String] = []
        while p < end, s[p] == T.at {
            guard let (name, after) = T.word(s, at: p + 1, end: end) else { break }
            var q = after
            if q < end, s[q] == T.openParen {
                guard let close = attributeArguments(s, q, end) else { break }
                q = close + 1
            }
            let next = T.skipBlanks(s, q, end)
            guard next > q else { break }
            attrs.append("@" + name + (q > after ? T.string(s[after..<q]) : ""))
            p = next
        }
        // Modifiers, greedily; `class` is a modifier and a keyword, so a keyword that does not follow them is tried
        // where the last modifier began.
        var starts: [(start: Int, word: String)] = []
        var q = p
        while let (word, after) = T.word(s, at: q, end: end), modifiers.contains(word) {
            var r = after
            if r < end, s[r] == T.openParen {
                var k = r + 1
                while k < end, s[k] != T.closeParen, s[k] != T.newline { k += 1 }
                guard k < end, s[k] == T.closeParen else { break }
                r = k + 1
            }
            let next = T.skipBlanks(s, r, end)
            guard next > r else { break }
            starts.append((q, word))
            q = next
        }
        var at = q
        while true {
            if let (word, after) = T.word(s, at: at, end: end), keywords.contains(word), !(after < end && T.isWord(s[after])) {
                let mods = starts.filter { $0.start < at }.map(\.word).joined(separator: " ")
                return Match(lead: lead, attrs: attrs, mods: mods, keyword: word, keywordOffset: at, end: after)
            }
            guard let last = starts.popLast() else { return nil }
            at = last.start
        }
    }

    /// The `)` closing an attribute's arguments: one level of nested parentheses, all on one line.
    private static func attributeArguments(_ s: [UInt16], _ open: Int, _ end: Int) -> Int? {
        var depth = 0
        var k = open
        while k < end {
            let c = s[k]
            if c == SwiftText.newline { return nil }
            if c == SwiftText.openParen {
                depth += 1
                if depth > 2 { return nil }
            } else if c == SwiftText.closeParen {
                depth -= 1
                if depth == 0 { return k }
            }
            k += 1
        }
        return nil
    }

    /// The declaration a brace opens, read back from the brace over `s[start..<brace]`: nil when the brace is a block.
    static func find(_ s: [UInt16], start: Int, brace: Int) -> (Match, Shape)? {
        var lineStarts = [start]
        for k in start..<brace where s[k] == SwiftText.newline || s[k] == SwiftText.semicolon { lineStarts.append(k + 1) }
        for from in lineStarts.reversed() {
            guard let m = match(s, from: from, end: brace) else { continue }
            guard let shape = shape(m.keyword, Array(s[m.end..<brace])) else { return nil }
            return (m, shape)
        }
        return nil
    }

    /// Checks what follows a keyword up to its brace (or the end of a requirement): the name and the parameters, or
    /// nil when the brace is not this declaration's.
    static func shape(_ keyword: String, _ rest: [UInt16]) -> Shape? {
        typealias T = SwiftText
        let n = rest.count
        switch keyword {
        case "func", "init", "subscript":
            var p = 0
            var name: String
            if keyword == "func" {
                p = T.skipWhite(rest, 0, n)
                if p < n, rest[p] == T.backtick {
                    var k = p + 1
                    while k < n, rest[k] != T.backtick { k += 1 }
                    guard k < n, k > p + 1 else { return nil }
                    name = T.string(rest[(p + 1)..<k])
                    p = k + 1
                } else if let (word, after) = T.word(rest, at: p, end: n) {
                    name = word
                    p = after
                } else {
                    var k = p
                    while k < n, operatorUnits.contains(rest[k]) { k += 1 }
                    guard k > p else { return nil }
                    // `func ==<T: Equatable>(…)`: the operator ends where its generic clause begins.
                    var cut = k
                    if T.skipWhite(rest, k, n) >= n || rest[T.skipWhite(rest, k, n)] != T.openParen {
                        for c in stride(from: k - 1, to: p, by: -1) where rest[c] == T.less {
                            if let after = skipAngles(rest, c), T.skipWhite(rest, after, n) < n, rest[T.skipWhite(rest, after, n)] == T.openParen {
                                cut = c
                                break
                            }
                        }
                    }
                    name = T.string(rest[p..<cut])
                    p = cut
                }
                p = T.skipWhite(rest, p, n)
            } else if keyword == "init" {
                name = "init"
                if p < n, rest[p] == T.question || rest[p] == T.bang { p += 1 }
                p = T.skipWhite(rest, p, n)
            } else {
                name = "subscript"
                p = T.skipWhite(rest, 0, n)
            }
            if p < n, rest[p] == T.less {
                guard let after = skipAngles(rest, p) else { return nil }
                p = T.skipWhite(rest, after, n)
            }
            guard p < n, rest[p] == T.openParen, let q = T.closingParen(rest, p) else { return nil }
            if T.assignment(T.topLevel(rest[(q + 1)...])) != nil { return nil }
            let isOperator = !name.isEmpty && name.utf16.allSatisfy { operatorUnits.contains($0) }
            return Shape(name: name, params: parameters(Array(rest[(p + 1)..<q])), isOperator: isOperator)
        case "deinit":
            return T.trimmed(rest).isEmpty ? Shape(name: "deinit", params: [], isOperator: false) : nil
        case "var":
            let stripped = T.trimmed(rest)
            if stripped.contains(T.newline) || T.assignment(T.topLevel(rest)) != nil { return nil }
            var p = T.skipWhite(rest, 0, n)
            guard let (name, after) = identifier(rest, p) else { return nil }
            p = T.skipWhite(rest, after, n)
            guard p < n, rest[p] == T.colon else { return nil }
            p = T.skipWhite(rest, p + 1, n)
            guard p < n else { return nil }
            return Shape(name: name, params: [], isOperator: false)
        case "let":
            return nil
        case "extension":
            let p = T.skipWhite(rest, 0, n)
            guard p < n, T.isIdentStart(rest[p]) else { return nil }
            var k = p + 1
            while k < n, T.isWord(rest[k]) || rest[k] == T.dot { k += 1 }
            if T.assignment(T.topLevel(rest)) != nil { return nil }
            return Shape(name: T.string(rest[p..<k]), params: [], isOperator: false)
        default:
            let p = T.skipWhite(rest, 0, n)
            guard let (name, _) = identifier(rest, p), T.assignment(T.topLevel(rest)) == nil else { return nil }
            return Shape(name: name, params: [], isOperator: false)
        }
    }

    /// A name at `p`: a word, or a backticked one.
    static func identifier(_ s: [UInt16], _ p: Int) -> (String, Int)? {
        guard p < s.count else { return nil }
        if s[p] == SwiftText.backtick {
            var k = p + 1
            while k < s.count, s[k] != SwiftText.backtick { k += 1 }
            guard k < s.count, k > p + 1 else { return nil }
            return (SwiftText.string(s[(p + 1)..<k]), k + 1)
        }
        return SwiftText.word(s, at: p)
    }

    /// Past the `>` that closes the `<` at `p`; an arrow's `>` does not close it.
    static func skipAngles(_ s: [UInt16], _ p: Int) -> Int? {
        var depth = 0
        var k = p
        while k < s.count {
            if s[k] == SwiftText.less { depth += 1 } else if s[k] == SwiftText.greater, k == 0 || s[k - 1] != SwiftText.minus {
                depth -= 1
                if depth == 0 { return k + 1 }
            }
            k += 1
        }
        return nil
    }

    private static let arrow: [UInt16] = Array("->".utf16)
    private static let ellipsis: [UInt16] = Array("...".utf16)

    /// The parameters of a declaration's list. A comma inside a generic type cuts a fragment with no colon, which is
    /// dropped.
    static func parameters(_ text: [UInt16]) -> [Param] {
        typealias T = SwiftText
        var out: [Param] = []
        for fragment in T.splitTop(text, T.comma) {
            guard let k = T.firstTop(fragment, T.colon) else { continue }
            let words = T.string(fragment[..<k]).split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
                .filter { !$0.hasPrefix("@") }
            guard let first = words.first, words.count <= 2, isLabel(String(first)) else { continue }
            let after = Array(fragment[(k + 1)...])
            let rest = T.topLevel(after)
            // An optional closure is wrapped in parens, `(@Sendable (Int) -> Void)? = nil`: its arrow sits one level in.
            var kind = T.trimmed(T.beforeAssignment(after))
            while let first = kind.first, first == T.at {
                var q = 1
                while q < kind.count, T.isWord(kind[q]) { q += 1 }
                if q < kind.count, kind[q] == T.openParen, let close = T.closingParen(kind, q) { q = close + 1 }
                kind = T.trimmed(Array(kind[q...]))
            }
            while let last = kind.last, last == T.question || last == T.bang { kind.removeLast() }
            var wrapped = false
            if kind.count >= 2, kind.first == T.openParen, kind.last == T.closeParen {
                wrapped = T.contains(T.topLevel(kind[1..<(kind.count - 1)]), arrow)
            }
            let typeText = T.trimmed(T.beforeAssignment(rest))
            let isVariadic = typeText.count >= 3 && Array(typeText.suffix(3)) == ellipsis
            out.append(Param(label: String(first).replacingOccurrences(of: "`", with: ""), hasDefault: T.assignment(rest) != nil,
                             isClosure: T.contains(rest, arrow) || wrapped, isVariadic: isVariadic))
        }
        return out
    }

    private static func isLabel(_ word: String) -> Bool {
        if word == "_" { return true }
        let bare = word.hasPrefix("`") && word.hasSuffix("`") && word.count > 2 ? String(word.dropFirst().dropLast()) : word
        guard let first = bare.utf16.first, SwiftText.isIdentStart(first) else { return false }
        return bare.utf16.allSatisfy(SwiftText.isWord)
    }
}
