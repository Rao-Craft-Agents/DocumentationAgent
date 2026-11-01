//  WHAT: Text as UTF-16 code units, the unit a browser's JavaScript counts in, and the small scans the lexer, the walk
//        and the call matcher share: words, brackets at the top level, a lone `=`, a closing parenthesis.
//  PIN:  UTF-16, NOT CHARACTERS. Every offset this package writes into the site (a brace's column, a call's place) is
//        read back by the page with `String.slice`, which counts UTF-16 units; counting the same way here keeps a file
//        with an emoji or an accented name from drifting by a column.

import Foundation

enum SwiftText {
    static let tab: UInt16 = 9, newline: UInt16 = 10, carriage: UInt16 = 13, space: UInt16 = 32
    static let bang: UInt16 = 33, quote: UInt16 = 34, hash: UInt16 = 35, dollar: UInt16 = 36, percent: UInt16 = 37
    static let amp: UInt16 = 38, openParen: UInt16 = 40, closeParen: UInt16 = 41, star: UInt16 = 42, plus: UInt16 = 43
    static let comma: UInt16 = 44, minus: UInt16 = 45, dot: UInt16 = 46, slash: UInt16 = 47, colon: UInt16 = 58
    static let semicolon: UInt16 = 59, less: UInt16 = 60, equals: UInt16 = 61, greater: UInt16 = 62, question: UInt16 = 63
    static let at: UInt16 = 64, openBracket: UInt16 = 91, backslash: UInt16 = 92, closeBracket: UInt16 = 93
    static let caret: UInt16 = 94, underscore: UInt16 = 95, backtick: UInt16 = 96, openBrace: UInt16 = 123
    static let bar: UInt16 = 124, closeBrace: UInt16 = 125, tilde: UInt16 = 126

    static func units(_ text: String) -> [UInt16] { Array(text.utf16) }

    static func string<C: Collection>(_ units: C) -> String where C.Element == UInt16 { String(decoding: units, as: UTF16.self) }

    /// A letter, a digit or `_`; a unit past ASCII counts as a letter, as Swift names may hold one.
    @inline(__always) static func isWord(_ u: UInt16) -> Bool {
        (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == underscore || u >= 0xC0
    }

    @inline(__always) static func isIdentStart(_ u: UInt16) -> Bool {
        (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == underscore || u >= 0xC0
    }

    @inline(__always) static func isDigit(_ u: UInt16) -> Bool { u >= 48 && u <= 57 }
    @inline(__always) static func isUpper(_ u: UInt16) -> Bool { u >= 65 && u <= 90 }
    @inline(__always) static func isBlank(_ u: UInt16) -> Bool { u == space || u == tab }
    @inline(__always) static func isWhite(_ u: UInt16) -> Bool { u == space || u == tab || u == newline || u == carriage }

    /// The line starts of `units`: line n (from 1) starts at `starts[n - 1]`.
    static func lineStarts(_ units: [UInt16]) -> [Int] {
        var starts = [0]
        for i in units.indices where units[i] == newline { starts.append(i + 1) }
        return starts
    }

    /// The line (from 1) that holds `offset`: how many line starts are at or before it.
    static func line(of offset: Int, starts: [Int]) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Whether `units` holds `word` at `at`.
    static func has(_ units: [UInt16], _ word: [UInt16], at: Int) -> Bool {
        guard at >= 0, at + word.count <= units.count else { return false }
        for k in 0..<word.count where units[at + k] != word[k] { return false }
        return true
    }

    /// The word starting at `at` (letters, digits, `_`), and where it ends.
    static func word(_ units: [UInt16], at: Int, end: Int? = nil) -> (String, Int)? {
        let stop = end ?? units.count
        guard at < stop, isIdentStart(units[at]) else { return nil }
        var k = at + 1
        while k < stop, isWord(units[k]) { k += 1 }
        return (string(units[at..<k]), k)
    }

    /// The index after the run of spaces and tabs at `at`.
    static func skipBlanks(_ units: [UInt16], _ at: Int, _ end: Int) -> Int {
        var k = at
        while k < end, isBlank(units[k]) { k += 1 }
        return k
    }

    /// The index after the run of whitespace, newlines included, at `at`.
    static func skipWhite(_ units: [UInt16], _ at: Int, _ end: Int) -> Int {
        var k = at
        while k < end, isWhite(units[k]) { k += 1 }
        return k
    }

    /// The `)` that closes the `(` at `open`, counting only parentheses.
    static func closingParen<C: RandomAccessCollection>(_ s: C, _ open: C.Index) -> C.Index? where C.Element == UInt16 {
        var depth = 0
        var k = open
        while k < s.endIndex {
            let c = s[k]
            if c == openParen { depth += 1 } else if c == closeParen {
                depth -= 1
                if depth == 0 { return k }
            }
            k = s.index(after: k)
        }
        return nil
    }

    /// The `}` that closes the `{` at `open`; the end when it never closes.
    static func closingBrace(_ s: [UInt16], _ open: Int) -> Int {
        var depth = 0
        for k in open..<s.count {
            if s[k] == openBrace { depth += 1 } else if s[k] == closeBrace {
                depth -= 1
                if depth == 0 { return k }
            }
        }
        return s.count
    }

    /// The text outside every (), [] and {}.
    static func topLevel<C: Collection>(_ s: C) -> [UInt16] where C.Element == UInt16 {
        var out: [UInt16] = [], depth = 0
        for c in s {
            if c == openParen || c == openBracket || c == openBrace { depth += 1 }
            else if c == closeParen || c == closeBracket || c == closeBrace { depth -= 1 }
            else if depth == 0 { out.append(c) }
        }
        return out
    }

    /// `s` cut at every `separator` outside (), [] and {}.
    static func splitTop<C: Collection>(_ s: C, _ separator: UInt16) -> [[UInt16]] where C.Element == UInt16 {
        var parts: [[UInt16]] = [], current: [UInt16] = [], depth = 0
        for c in s {
            if c == openParen || c == openBracket || c == openBrace { depth += 1 }
            else if c == closeParen || c == closeBracket || c == closeBrace { depth -= 1 }
            if c == separator && depth == 0 {
                parts.append(current)
                current = []
            } else {
                current.append(c)
            }
        }
        parts.append(current)
        return parts
    }

    /// The first `ch` outside (), [] and {}.
    static func firstTop(_ s: [UInt16], _ ch: UInt16) -> Int? {
        var depth = 0
        for (k, c) in s.enumerated() {
            if c == openParen || c == openBracket || c == openBrace { depth += 1 }
            else if c == closeParen || c == closeBracket || c == closeBrace { depth -= 1 }
            else if c == ch && depth == 0 { return k }
        }
        return nil
    }

    /// Where the first lone `=` is: not part of `==`, `!=`, `<=`, `>=`, `=>`, `->` or `===`.
    static func assignment(_ s: [UInt16]) -> Int? {
        for k in s.indices where s[k] == equals {
            let before: UInt16 = k > 0 ? s[k - 1] : 0
            let after: UInt16 = k + 1 < s.count ? s[k + 1] : 0
            if before == equals || before == bang || before == less || before == greater { continue }
            if after == equals || after == greater { continue }
            return k
        }
        return nil
    }

    /// `s` before its first lone `=`.
    static func beforeAssignment(_ s: [UInt16]) -> [UInt16] {
        guard let k = assignment(s) else { return s }
        return Array(s[..<k])
    }

    static func trimmed(_ s: [UInt16]) -> [UInt16] {
        var a = 0, b = s.count
        while a < b, isWhite(s[a]) { a += 1 }
        while b > a, isWhite(s[b - 1]) { b -= 1 }
        return Array(s[a..<b])
    }

    static func contains(_ s: [UInt16], _ word: [UInt16]) -> Bool {
        guard !word.isEmpty, s.count >= word.count else { return false }
        for k in 0...(s.count - word.count) where s[k] == word[0] && has(s, word, at: k) { return true }
        return false
    }
}
