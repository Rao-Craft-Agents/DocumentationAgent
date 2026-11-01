import Foundation
import XCTest
@testable import DocumentationAgent

/// The checks every answer of the model passes before it is written.
final class ProseTests: XCTestCase {
    private let digest = ProseDigest(text: "Project: Tally\n- Sources/Tally/App.swift: the app.\n- Sources/Tally/Store.swift: the store.",
                                     citable: ["Sources/Tally/App.swift", "Sources/Tally/Store.swift", "Sources/Other/Store.swift"])

    private func problems(_ claims: [(String, [String])], features: [(String, String, [String])]? = nil, range: ClosedRange<Int> = 1...3) -> (ProseAnswer, [String]) {
        var answer = ProseAnswer(sentences: claims.map { .init(text: $0.0, files: $0.1) },
                                 features: features.map { $0.map { .init(title: $0.0, text: $0.1, files: $0.2) } })
        let found = ProseCheck.problems(&answer, digest: digest, sentences: range, features: features == nil ? nil : 1...5)
        return (answer, found)
    }

    func testAGoodAnswerPassesAndItsBareNamesBecomePaths() {
        let (answer, found) = problems([("Tally keeps a household's spending in one store that the app reads.", ["App.swift", "Sources/Tally/App.swift:12"])])
        XCTAssertEqual(found, [])
        XCTAssertEqual(answer.sentences[0].files, ["Sources/Tally/App.swift"], "a bare name the digest has once, and a path with a line, both resolve")
    }

    func testEveryProblemIsSaid() {
        let (_, found) = problems([
            ("Short.", ["Sources/Tally/App.swift"]),
            ("A seamless app with a [link](https://example.com) in it.", ["Store.swift"]),
            ("It does one thing. Then another thing entirely, as a second sentence.", ["Sources/Tally/Gone.swift"]),
            ("It has no period at the end", []),
        ])
        for problem in ["give 1 to 3 sentences, not 4", "sentence 1 is too short", "`seamless`", "`[`", "`https://`", "cites `Store.swift`, which is not a file the digest names",
                        "sentence 3 is more than one sentence", "cites `Sources/Tally/Gone.swift`", "sentence 4 does not end with a period", "sentence 4 cites no file"] {
            XCTAssertTrue(found.contains { $0.contains(problem) }, "\(problem) in \(found)")
        }
    }

    func testAPlaceholderPassesOnlyWhenTheCodeUsesTheWord() {
        XCTAssertTrue(problems([("The app shows a TODO list of what is left to pay this month.", ["App.swift"])]).1.contains { $0.contains("placeholder") })
        let todo = ProseDigest(text: digest.text + "\n- Sources/Tally/Todo.swift: a todo list.", citable: digest.citable)
        var answer = ProseAnswer(sentences: [.init(text: "The app shows a todo list of what is left to pay this month.", files: ["App.swift"])], features: nil)
        XCTAssertEqual(ProseCheck.problems(&answer, digest: todo, sentences: 1...3, features: nil), [])
    }

    func testTheExamplesWordsAreCaught() {
        XCTAssertTrue(ProseCheck.echoes("Larder is a pantry and meal planner for iPhone and Mac."))
        XCTAssertFalse(ProseCheck.echoes("Tally keeps a household's spending beside its budgets."))
    }

    func testTheSchemaAsksForFeaturesOnlyWhenWanted() throws {
        let with = try XCTUnwrap(JSONSerialization.jsonObject(with: ProsePrompt.schema(features: true)) as? [String: Any])
        let without = try XCTUnwrap(JSONSerialization.jsonObject(with: ProsePrompt.schema(features: false)) as? [String: Any])
        XCTAssertEqual(with["required"] as? [String], ["sentences", "features"])
        XCTAssertEqual(without["required"] as? [String], ["sentences"])
        let example = try JSONDecoder().decode(ProseAnswer.self, from: Data(ProsePrompt.readmeExample.utf8))
        XCTAssertEqual(example.features?.count, 3, "the worked example decodes as an answer")
    }
}
