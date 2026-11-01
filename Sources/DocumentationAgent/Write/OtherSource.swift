//  WHAT: What a file in another language says it is: its module docstring or its opening comment block, past a licence
//        header and an editor's template, in a sentence. Files of other languages get pages and search; Swift alone is
//        walked for declarations.

import Foundation

enum OtherSource {
    static func summary(_ file: ProjectFile) -> String {
        var kept: [String] = []
        var inBlock = false, inDocstring = false
        for raw in file.text.components(separatedBy: "\n").prefix(60) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#!") || (line.isEmpty && kept.isEmpty && !inBlock && !inDocstring) { continue }
            if inDocstring {
                if line.contains("\"\"\"") { kept.append(line.replacingOccurrences(of: "\"\"\"", with: "")); break }
                kept.append(line)
                continue
            }
            if inBlock {
                if line.contains("*/") { kept.append(line.replacingOccurrences(of: "*/", with: "")); inBlock = false; if !kept.joined().trimmingCharacters(in: .whitespaces).isEmpty { break }; continue }
                kept.append(line.drop { $0 == "*" }.trimmingCharacters(in: .whitespaces))
                continue
            }
            if line.hasPrefix("\"\"\"") {
                let rest = String(line.dropFirst(3))
                if rest.contains("\"\"\"") { kept.append(rest.replacingOccurrences(of: "\"\"\"", with: "")); break }
                kept.append(rest)
                inDocstring = true
                continue
            }
            if line.hasPrefix("/*") { inBlock = !line.contains("*/"); kept.append(line.dropFirst(2).replacingOccurrences(of: "*/", with: "").drop { $0 == "*" }.trimmingCharacters(in: .whitespaces)); continue }
            if line.hasPrefix("//") { kept.append(line.drop { $0 == "/" }.trimmingCharacters(in: .whitespaces)); continue }
            if line.hasPrefix("#") && !line.hasPrefix("#include") && !line.hasPrefix("#import") && !line.hasPrefix("#if") && !line.hasPrefix("#define") && !line.hasPrefix("#pragma") {
                kept.append(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                continue
            }
            break
        }
        let prose = kept.filter { line in
            !line.isEmpty && !line.localizedCaseInsensitiveContains("copyright") && !line.localizedCaseInsensitiveContains("license")
                && !line.hasPrefix("Created by") && !line.hasPrefix("@") && !line.hasPrefix("eslint") && !line.hasPrefix("-*-") && line != file.name
                && line.contains(" ")
        }.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return prose.isEmpty ? "" : SwiftSource.firstSentence(String(prose.prefix(400)))
    }
}
