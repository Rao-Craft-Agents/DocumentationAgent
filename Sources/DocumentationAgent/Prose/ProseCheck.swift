//  WHAT: The checks every answer of the model passes before it is written: a few sentences, each one sentence and
//        bounded, each citing files the digest named, no placeholder, no markup, no marketing, and nothing copied from
//        the worked example. Every problem is said, so a retry can fix them all.

import Foundation

enum ProseCheck {
    /// Never written: markup, a link, a template's braces.
    static let markup = ["```", "{{", "}}", "<", ">", "[", "]", "](", "http://", "https://"]
    /// Placeholder words, written only when the project's own code uses them.
    static let placeholders = ["todo", "tbd", "lorem", "ipsum", "placeholder", "xxx", "insert here", "your app", "your project", "example.com"]
    static let marketing = ["powerful", "seamless", "robust", "blazing", "effortless", "cutting-edge", "cutting edge", "state-of-the-art",
                            "revolutionary", "world-class", "simply", "best-in-class", "next-generation"]

    /// The problems with `answer`, one sentence each; empty when it may be written. Cited paths are resolved against
    /// `digest.citable` in place: a bare file name the digest has once becomes its path.
    static func problems(_ answer: inout ProseAnswer, digest: ProseDigest, sentences range: ClosedRange<Int>, features: ClosedRange<Int>?) -> [String] {
        var problems: [String] = []
        if !range.contains(answer.sentences.count) { problems.append("give \(range.lowerBound) to \(range.upperBound) sentences, not \(answer.sentences.count)") }
        for i in answer.sentences.indices {
            problems += check(text: answer.sentences[i].text, what: "sentence \(i + 1)", maxLength: 240, digest: digest)
            problems += resolve(&answer.sentences[i].files, what: "sentence \(i + 1)", digest: digest)
        }
        if let features {
            let list = answer.features ?? []
            if !features.contains(list.count) { problems.append("give \(features.lowerBound) to \(features.upperBound) features, not \(list.count)") }
            for i in list.indices {
                let title = list[i].title.trimmingCharacters(in: .whitespaces)
                if title.count < 3 || title.count > 48 || title.contains(".") { problems.append("feature \(i + 1)'s title must be two to five words with no period") }
                problems += check(text: list[i].text, what: "feature \(i + 1)", maxLength: 220, digest: digest)
                problems += resolve(&answer.features![i].files, what: "feature \(i + 1)", digest: digest)
            }
        }
        let all = answer.sentences.map(\.text) + (answer.features ?? []).flatMap { [$0.title, $0.text] }
        if all.contains(where: echoes) { problems.append("the answer repeats the worked example's words; write about this project from its digest") }
        return problems
    }

    private static func check(text: String, what: String, maxLength: Int, digest: ProseDigest) -> [String] {
        var problems: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.count < 20 { problems.append("\(what) is too short to say anything") }
        if trimmed.count > maxLength { problems.append("\(what) is \(trimmed.count) characters; at most \(maxLength)") }
        if trimmed.contains("\n") { problems.append("\(what) runs over more than one line") }
        if !(trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")) { problems.append("\(what) does not end with a period") }
        let inner = trimmed.dropLast().replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(e\.g|i\.e|etc|vs)\."#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.[A-Za-z0-9]"#, with: "", options: .regularExpression)
        if inner.contains(". ") { problems.append("\(what) is more than one sentence") }
        for mark in markup where trimmed.contains(mark) { problems.append("\(what) holds `\(mark)`: no Markdown, links or templates, only plain sentences") }
        for word in placeholders where lower.range(of: "\\b\(word)\\b", options: .regularExpression) != nil && !digest.text.lowercased().contains(word) {
            problems.append("\(what) holds `\(word)`, a placeholder, not something the code says")
        }
        for word in marketing where lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil {
            problems.append("\(what) says `\(word)`: say what the code does instead")
        }
        return problems
    }

    private static func resolve(_ files: inout [String], what: String, digest: ProseDigest) -> [String] {
        if files.isEmpty { return ["\(what) cites no file; name the files in the digest that show it"] }
        if files.count > 3 { return ["\(what) cites \(files.count) files; at most three"] }
        var problems: [String] = []
        for i in files.indices {
            let named = files[i].trimmingCharacters(in: CharacterSet(charactersIn: " `'\"")).replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression)
            if digest.citable.contains(named) { files[i] = named; continue }
            let matches = digest.citable.filter { $0.hasSuffix("/" + named) }
            if matches.count == 1 { files[i] = matches.first!; continue }
            problems.append("\(what) cites `\(files[i])`, which is not a file the digest names")
        }
        var seen: Set<String> = []
        files = files.filter { seen.insert($0).inserted }
        return problems
    }

    /// Whether `text` repeats two words in a row of the worked examples, past the common ones.
    static func echoes(_ text: String) -> Bool { !pairs(text).isDisjoint(with: examplePairs) }

    private static let examplePairs: Set<String> = {
        var said: [String] = []
        for example in [ProsePrompt.readmeExample, ProsePrompt.folderExample] {
            if let answer = try? JSONDecoder().decode(ProseAnswer.self, from: Data(example.utf8)) {
                said += answer.sentences.map(\.text) + (answer.features ?? []).flatMap { [$0.title, $0.text] }
            }
        }
        return said.reduce(into: Set<String>()) { $0.formUnion(pairs($1)) }
    }()

    private static func pairs(_ text: String) -> Set<String> {
        let common: Set<String> = ["the", "and", "its", "that", "what", "with", "from", "this", "each", "one", "for", "when", "are", "was", "has",
                                   "own", "into", "through", "their", "they", "them", "then", "folder", "holds", "service", "services", "reducer",
                                   "reducers", "events", "event", "center", "component", "components", "screen", "every", "keeps"]
        let words = text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 && !common.contains($0) }
        return Set(zip(words, words.dropFirst()).map { "\($0) \($1)" })
    }
}
