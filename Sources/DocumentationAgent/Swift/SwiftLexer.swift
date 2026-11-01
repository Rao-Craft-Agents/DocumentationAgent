//  WHAT: One pass over a Swift file: its text with strings, regex literals and comments blanked to spaces (newlines
//        and the code inside interpolations kept), every brace with its line and the paren, bracket and frame depth
//        it sits at, the lines that are `///` doc comments, and the MARK lines. Ported from Craft's site builder.
//  PIN:  A LEXER, NOT A COMPILER. It knows strings (raw, multi-line, interpolated), `#/…/#` regex literals and nested
//        block comments, which is what a brace walk needs to never count a brace inside text. A file it cannot read
//        to the end says why in `problem`, and the walk then leaves it with no declarations rather than wrong ones.

import Foundation

enum SwiftLexer {
    struct Brace: Sendable {
        let offset: Int
        let open: Bool
        let line: Int
        let paren: Int
        let bracket: Int
        /// 1 at the top level; more inside a string's interpolation.
        let depth: Int
    }

    struct Mark: Sendable {
        let line: Int
        let text: String
    }

    struct Output: Sendable {
        var blank: [UInt16]
        var braces: [Brace]
        var doc: Set<Int>
        var marks: [Mark]
        var problem: String?
    }

    private enum Frame {
        case code(paren: Int, bracket: Int)
        case string(hashes: Int, multi: Bool)
        case comment(depth: Int)
    }

    private static let tripleQuote: [UInt16] = Array("\"\"\"".utf16)
    private static let markWord: [UInt16] = Array("MARK:".utf16)

    static func lex(_ t: [UInt16]) -> Output {
        typealias T = SwiftText
        var out = t
        var braces: [Brace] = [], doc: Set<Int> = [], marks: [Mark] = []
        var stack: [Frame] = [.code(paren: 0, bracket: 0)]
        let n = t.count
        var i = 0, line = 1
        @inline(__always) func blank(_ a: Int, _ b: Int) {
            var k = a
            while k < min(b, n) { out[k] = T.space; k += 1 }
        }
        func hashes(_ count: Int) -> [UInt16] { Array(repeating: T.hash, count: count) }
        func fail(_ why: String) -> Output { Output(blank: out, braces: braces, doc: doc, marks: marks, problem: "line \(line): \(why)") }

        while i < n {
            switch stack[stack.count - 1] {
            case .code(var paren, var bracket):
                var j = i
                while j < n {
                    let c = t[j]
                    if c == T.slash || c == T.quote || c == T.hash || c == T.openParen || c == T.closeParen || c == T.openBracket
                        || c == T.closeBracket || c == T.openBrace || c == T.closeBrace || c == T.newline { break }
                    j += 1
                }
                if j >= n { i = n; continue }
                let ch = t[j]
                switch ch {
                case T.newline:
                    line += 1
                    i = j + 1
                case T.slash:
                    let next: UInt16 = j + 1 < n ? t[j + 1] : 0
                    if next == T.slash {
                        var e = j
                        while e < n, t[e] != T.newline { e += 1 }
                        let isDoc = j + 2 < n && t[j + 2] == T.slash && !(j + 3 < n && t[j + 3] == T.slash)
                        if isDoc { doc.insert(line) }
                        var k = T.skipBlanks(t, j + 2, e)
                        if T.has(t, markWord, at: k) {
                            k = T.skipBlanks(t, k + markWord.count, e)
                            if k < e, t[k] == T.minus { k = T.skipBlanks(t, k + 1, e) }
                            marks.append(Mark(line: line, text: T.string(T.trimmed(Array(t[k..<e])))))
                        }
                        blank(j, e)
                        i = e
                    } else if next == T.star {
                        stack.append(.comment(depth: 1))
                        blank(j, j + 2)
                        i = j + 2
                    } else {
                        i = j + 1
                    }
                case T.hash:
                    var k = j
                    while k < n, t[k] == T.hash { k += 1 }
                    if k < n, t[k] == T.quote {
                        let multi = T.has(t, tripleQuote, at: k)
                        let end = k + (multi ? 3 : 1)
                        blank(j, end)
                        stack.append(.string(hashes: k - j, multi: multi))
                        i = end
                    } else if k < n, t[k] == T.slash {
                        // An extended regex literal, #/…/#: its text holds no code, and may hold quotes and braces.
                        let closer = [T.slash] + hashes(k - j)
                        var close = k + 1
                        while close < n, !T.has(t, closer, at: close) { close += 1 }
                        if close >= n { return fail("a regex literal never ends") }
                        let stop = close + closer.count
                        for p in j..<stop where t[p] == T.newline { line += 1 }
                        for p in j..<stop where t[p] != T.newline { out[p] = T.space }
                        i = stop
                    } else {
                        i = k
                    }
                case T.quote:
                    let multi = T.has(t, tripleQuote, at: j)
                    let end = j + (multi ? 3 : 1)
                    blank(j, end)
                    stack.append(.string(hashes: 0, multi: multi))
                    i = end
                case T.openParen:
                    paren += 1
                    stack[stack.count - 1] = .code(paren: paren, bracket: bracket)
                    i = j + 1
                case T.closeParen:
                    if paren == 0 && stack.count > 1 {
                        blank(j, j + 1)  // the end of an interpolation
                        stack.removeLast()
                    } else {
                        paren -= 1
                        stack[stack.count - 1] = .code(paren: paren, bracket: bracket)
                    }
                    i = j + 1
                case T.openBracket:
                    bracket += 1
                    stack[stack.count - 1] = .code(paren: paren, bracket: bracket)
                    i = j + 1
                case T.closeBracket:
                    bracket -= 1
                    stack[stack.count - 1] = .code(paren: paren, bracket: bracket)
                    i = j + 1
                default:
                    braces.append(Brace(offset: j, open: ch == T.openBrace, line: line, paren: paren, bracket: bracket, depth: stack.count))
                    i = j + 1
                }
            case .string(let count, let multi):
                var j = i
                while j < n, t[j] != T.quote, t[j] != T.backslash, t[j] != T.newline { j += 1 }
                if j >= n { return fail("a string never ends") }
                blank(i, j)
                let ch = t[j]
                if ch == T.newline {
                    if !multi { return fail("a string runs past the end of its line") }
                    line += 1
                    i = j + 1
                } else if ch == T.backslash {
                    if T.has(t, hashes(count) + [T.openParen], at: j + 1) {
                        blank(j, j + 2 + count)
                        stack.append(.code(paren: 0, bracket: 0))
                        i = j + 2 + count
                    } else if count == 0 {
                        if j + 1 < n, t[j + 1] == T.newline {
                            line += 1
                            blank(j, j + 1)
                        } else {
                            blank(j, j + 2)
                        }
                        i = j + 2
                    } else {
                        blank(j, j + 1)
                        i = j + 1
                    }
                } else if multi && T.has(t, tripleQuote + hashes(count), at: j) {
                    blank(j, j + 3 + count)
                    stack.removeLast()
                    i = j + 3 + count
                } else if !multi && T.has(t, [T.quote] + hashes(count), at: j) {
                    blank(j, j + 1 + count)
                    stack.removeLast()
                    i = j + 1 + count
                } else {
                    blank(j, j + 1)
                    i = j + 1
                }
            case .comment(let depth):
                var j = i
                while j < n {
                    let c = t[j]
                    if c == T.newline { break }
                    if c == T.slash, j + 1 < n, t[j + 1] == T.star { break }
                    if c == T.star, j + 1 < n, t[j + 1] == T.slash { break }
                    j += 1
                }
                if j >= n { return fail("a block comment never ends") }
                blank(i, j)
                if t[j] == T.newline {
                    line += 1
                    i = j + 1
                } else {
                    blank(j, j + 2)
                    let next = depth + (t[j] == T.slash ? 1 : -1)
                    if next == 0 { stack.removeLast() } else { stack[stack.count - 1] = .comment(depth: next) }
                    i = j + 2
                }
            }
        }
        if stack.count != 1 {
            if case .string = stack[stack.count - 1] { return fail("the file ends inside a string") }
            if case .comment = stack[stack.count - 1] { return fail("the file ends inside a comment") }
            return fail("the file ends inside an interpolation")
        }
        if case .code(let paren, let bracket) = stack[0], paren != 0 || bracket != 0 {
            return Output(blank: out, braces: braces, doc: doc, marks: marks, problem: "the file ends inside an open paren or bracket")
        }
        return Output(blank: out, braces: braces, doc: doc, marks: marks, problem: nil)
    }
}
