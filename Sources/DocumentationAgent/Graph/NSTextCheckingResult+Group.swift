//  WHAT: A match's group read as text, from the `NSString` or `String` it was run over.

import Foundation

extension NSTextCheckingResult {
    /// Group `i`'s text in `s`, or nil when it did not take part.
    func group(_ i: Int, in s: NSString) -> String? {
        let r = range(at: i)
        return r.location == NSNotFound ? nil : s.substring(with: r)
    }

    func group(_ i: Int, in text: String) -> String? {
        let r = range(at: i)
        guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
        return String(text[range])
    }
}
