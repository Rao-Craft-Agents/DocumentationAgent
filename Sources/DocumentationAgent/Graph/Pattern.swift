//  WHAT: A regular expression compiled once and run over a file's text as an `NSString`, so every range it answers is
//        in UTF-16 units, the offsets the lexer and the walk count in.

import Foundation

struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        do { regex = try NSRegularExpression(pattern: pattern, options: options) } catch { preconditionFailure("\(pattern): \(error)") }
    }

    func matches(_ s: NSString, in range: NSRange? = nil) -> [NSTextCheckingResult] {
        regex.matches(in: s as String, range: range ?? NSRange(location: 0, length: s.length))
    }

    func first(_ s: NSString, in range: NSRange? = nil) -> NSTextCheckingResult? {
        regex.firstMatch(in: s as String, range: range ?? NSRange(location: 0, length: s.length))
    }

    func matches(_ text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func first(_ text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
