//  WHAT: Small readings and writings of Markdown: a README's first paragraph as plain prose, text made safe inside a
//        Markdown table or link, and a relative link from one generated file to a file of the project.

import Foundation

enum Markdown {
    /// The paragraph a README introduces its project with: the first paragraph of prose before its first `##` heading
    /// (a plain one, or a `<p>` on one line), past its title, badges, images, quotes, lists and code, with links reduced
    /// to their words; nil when it has none of six words or more.
    static func firstParagraph(_ text: String, limit: Int = 420) -> String? {
        var paragraph: [String] = []
        var fenced = false
        func words(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }.count }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { fenced.toggle(); if !paragraph.isEmpty { break }; continue }
            if fenced { continue }
            if line.isEmpty {
                if !paragraph.isEmpty { if words(paragraph.joined(separator: " ")) >= 6 { break }; paragraph = [] }
                continue
            }
            if line.hasPrefix("## ") || line.hasPrefix("##\t") || line == "##" { break }
            if line.lowercased().hasPrefix("<p"), line.lowercased().hasSuffix("</p>") {
                let inner = line.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if paragraph.isEmpty, words(inner) >= 6 { paragraph = [inner]; break }
                continue
            }
            if line.hasPrefix("#") || line.hasPrefix("![") || line.hasPrefix("[![") || line.hasPrefix("<") || line.hasPrefix("|")
                || line.hasPrefix(">") || line.hasPrefix("---") || line.hasPrefix("===") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty, words(paragraph.joined(separator: " ")) >= 6 { break }
                paragraph = []
                continue
            }
            paragraph.append(line)
        }
        guard !paragraph.isEmpty, words(paragraph.joined(separator: " ")) >= 6 else { return nil }
        var prose = paragraph.joined(separator: " ")
        prose = prose.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        prose = prose.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        prose = prose.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        prose = prose.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        prose = prose.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard prose.count >= 12 else { return nil }
        if prose.count > limit {
            let cut = prose.prefix(limit)
            if let end = cut.lastIndex(where: { $0 == "." }) { return String(cut[...end]) }
            return String(cut).trimmingCharacters(in: .whitespaces) + "…"
        }
        return prose
    }

    /// A count as English writes it: `13,853`. The same digits on every Mac, whatever its locale.
    static func count(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + out
    }

    /// `text` safe in a table cell: no bar, no line break.
    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    /// A link target for `path` (from the project's root) as seen from a file in `from` (also from the root): each
    /// part of the path percent-encoded where Markdown needs it.
    static func link(_ path: String, from: String) -> String {
        let fromParts = from == "." || from.isEmpty ? [] : from.split(separator: "/").map(String.init)
        let up = Array(repeating: "..", count: fromParts.count)
        return (up + path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))) ?? String($0) })
            .joined(separator: "/")
    }

    /// `text` with what would break Markdown inline escaped: backticks kept, an HTML tag's angle brackets escaped.
    static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
