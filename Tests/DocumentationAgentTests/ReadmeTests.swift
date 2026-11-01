import Foundation
import GraniteAgents
import XCTest
@testable import DocumentationAgent

/// The README: its prose the model's, each claim citing a file of the digest it was shown; everything else read off
/// the code; and nothing written when the call cannot be honoured.
final class ReadmeTests: XCTestCase {
    static let ledger = "Sources/Tally/Services/LedgerService/LedgerService.swift"
    static let app = "Sources/Tally/TallyApp.swift"
    static let month = "Sources/Tally/Components/Month/Month.swift"
    static let budget = "Sources/Tally/Models/Budget.swift"

    static func answer(_ sentences: [(String, [String])], features: [(String, String, [String])]? = nil) -> Data {
        var object: [String: Any] = ["sentences": sentences.map { ["text": $0.0, "files": $0.1] }]
        if let features { object["features"] = features.map { ["title": $0.0, "text": $0.1, "files": $0.2] } }
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static let good = answer([
        ("Tally is a household ledger that keeps each month's spending beside the budgets it is held to.", [app, "LedgerService.swift"]),
        ("Each entry is recorded through the ledger service, which tells the budget service to load when it boots.", [ledger]),
    ], features: [
        ("Month at a glance", "The month view lists what the ledger holds, entry by entry.", [month]),
        ("Budgets that hold", "A budget says how much each kind of spending may take in a month.", [budget]),
        ("One writer", "Only the ledger's reducers change the entries.", [ledger]),
    ])

    private func readme(_ input: [String: Any], model: FakeHostModel?, in folder: URL) async throws -> (DocumentationResult, String) {
        var input = input
        input["make"] = "readme"
        let data = try JSONSerialization.data(withJSONObject: input)
        let answer = try await AnyAgentPackage(DocumentationAgent.self).perform(data, host: AgentHost(directory: folder.path, ask: "write the readme", model: model))
        let result = try JSONDecoder().decode(DocumentationResult.self, from: answer)
        return (result, try String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8))
    }

    func testTheOpeningAndFeaturesAreTheModelsAndEachCitesItsFiles() async throws {
        let folder = try Fixture.tally()
        let model = FakeHostModel([Self.good])
        let (result, text) = try await readme(["tagline": "Spending, month by month."], model: model, in: folder)
        XCTAssertEqual(result.notes, [])
        XCTAssertTrue(text.hasPrefix("# Tally\n\nSpending, month by month.\n\nTally is a household ledger"), text)
        XCTAssertTrue(text.contains("held to ([TallyApp.swift](Sources/Tally/TallyApp.swift), [LedgerService.swift](Sources/Tally/Services/LedgerService/LedgerService.swift))."),
                      "a bare file name the digest has once becomes its path, and each citation is a link: \(text)")
        XCTAssertTrue(text.contains("## Features\n\n- **Month at a glance**: The month view lists what the ledger holds, entry by entry ([Month.swift](Sources/Tally/Components/Month/Month.swift))."), text)
        XCTAssertEqual(model.asked.count, 1)
        let ask = model.asked[0]
        XCTAssertTrue(ask.system.contains("Larder"), "the worked example is another project's")
        XCTAssertTrue(ask.user.contains("The project is Tally"))
        XCTAssertTrue(ask.user.contains("LedgerService (\(Self.ledger)): events boot, record; reaches BudgetService"), "the digest is the code's: \(ask.user)")
        XCTAssertFalse(ask.user.contains("Tally keeps a household's spending"), "the README being written is never its own source")
        XCTAssertLessThan(ask.user.count, 14_000, "the digest is capped")
    }

    func testARefusedAnswerIsAskedAgainWithEveryProblem() async throws {
        let folder = try Fixture.tally()
        let bad = Self.answer([("Tally is a seamless ledger [TODO] for everyone", ["Sources/Tally/Nowhere.swift"])], features: [])
        let model = FakeHostModel([bad, Self.good])
        let notes = NoteBox()
        let data = try JSONSerialization.data(withJSONObject: ["make": "readme", "directory": folder.path])
        _ = try await AnyAgentPackage(DocumentationAgent.self).perform(data, host: AgentHost(directory: folder.path, model: model, note: { notes.append($0) }))
        XCTAssertEqual(model.asked.count, 2)
        let retry = model.asked[1].user
        for problem in ["give 2 to 4 sentences", "`seamless`", "`[`", "`todo`", "Nowhere.swift", "does not end with a period", "give 3 to 7 features"] {
            XCTAssertTrue(retry.contains(problem), "the retry says \(problem): \(retry.suffix(900))")
        }
        XCTAssertTrue(notes.lines.contains { $0.hasPrefix("round 1:") }, "\(notes.lines)")
        let text = try String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("Tally is a household ledger"))
        XCTAssertFalse(text.contains("seamless"))
    }

    func testAnAnswerThatNeverPassesIsLeftOutAndSaid() async throws {
        let folder = try Fixture.tally()
        let copied = Data(ProsePrompt.readmeExample.utf8)
        let (result, text) = try await readme(["rounds": 2], model: FakeHostModel([copied]), in: folder)
        XCTAssertFalse(text.contains("## Features"))
        XCTAssertFalse(text.contains("Larder"), "the example's words never land")
        XCTAssertEqual(result.notes.count, 1)
        XCTAssertTrue(result.notes[0].hasPrefix("the README's opening paragraph and feature list are left out"), result.notes[0])
        XCTAssertTrue(result.notes[0].contains("in 2 rounds"), result.notes[0])
    }

    func testWithNoModelTheProseIsLeftOutAndTheRestIsWritten() async throws {
        let folder = try Fixture.tally()
        let (result, text) = try await readme([:], model: nil, in: folder)
        XCTAssertEqual(result.notes, ["the README's opening paragraph and feature list are left out: the host offers no model"])
        XCTAssertEqual(result.paths, [folder.appendingPathComponent("README.md").path])
        for section in ["## Requirements", "## Building", "## Testing", "## Structure", "## How it is built", "### Services", "### Components",
                        "### Targets", "## License\n\nMIT: see [LICENSE](LICENSE)."] {
            XCTAssertTrue(text.contains(section), "the README has \(section)")
        }
        XCTAssertFalse(text.contains("## Features"))
        XCTAssertTrue(text.contains("- iOS 17 or later and macOS 14 or later (Package.swift)"))
        XCTAssertTrue(text.contains("```sh\n# The package\nswift build\n```"))
        XCTAssertTrue(text.contains("# The package's tests\nswift test"))
        XCTAssertTrue(text.contains("│   └── Tally/"), "the tree goes two folders deep: \(text)")
        XCTAssertTrue(text.hasPrefix("# Tally\n\nTally: a household ledger that keeps each month's spending beside the budgets it is held to. *(From [Package.swift](Package.swift).)*\n\n## Requirements"),
                      "with no model, what the code says the project is, cited: \(text.prefix(300))")
        XCTAssertTrue(text.contains("| [LedgerService](Sources/Tally/Services/LedgerService/LedgerService.swift) | 1 | `boot`, `record` | BudgetService |"), text)
        XCTAssertTrue(text.contains("| [Month](Sources/Tally/Components/Month/Month.swift) | LedgerService | `refresh` |"), text)
        XCTAssertTrue(text.contains("[Granite](https://github.com/riteshpakala/Granite.git) (branch main)"), text)
        XCTAssertFalse(text.contains("TODO") || text.contains("lorem"), "no placeholder anywhere")
    }

    func testThePersonsFeaturesAreWrittenAsTheyGaveThem() async throws {
        let folder = try Fixture.tally()
        let model = FakeHostModel([Self.answer([("Tally is a household ledger that keeps each month's spending beside the budgets it is held to.", [Self.app])])])
        let (_, text) = try await readme(["features": ["Budgets that roll over into the next month", "A chart of the month's spending"]], model: model, in: folder)
        XCTAssertTrue(text.contains("## Features\n\n- Budgets that roll over into the next month\n- A chart of the month's spending\n"), text)
        XCTAssertFalse(model.asked[0].system.contains("`features`"), "the model is asked for no features of its own")
    }

    func testALicenceIsWrittenWhenTheProjectHasNoneAndKeptWhenItHasOne() async throws {
        let folder = try Fixture.tally()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("LICENSE"))
        let (result, text) = try await readme(["license": "Apache-2.0"], model: nil, in: folder)
        let license = try String(contentsOf: folder.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(license.hasPrefix("\n                                 Apache License\n                           Version 2.0, January 2004\n"), "verbatim")
        XCTAssertTrue(license.contains("END OF TERMS AND CONDITIONS"))
        XCTAssertTrue(result.paths.contains(folder.appendingPathComponent("LICENSE").path))
        XCTAssertTrue(text.hasSuffix("## License\n\nApache-2.0: see [LICENSE](LICENSE).\n"), String(text.suffix(300)))
        let bsd = LicenseText.text(.bsd, year: 2026, holder: "the Tally authors")
        XCTAssertTrue(bsd.hasPrefix("BSD 3-Clause License\n\nCopyright (c) 2026, the Tally authors\nAll rights reserved.\n\nRedistribution and use"))
        let (kept, _) = try await readme(["license": "ISC"], model: nil, in: folder)
        XCTAssertTrue(kept.notes.contains("the project's LICENSE is Apache-2.0, not ISC; it was kept, and the README names it"), "\(kept.notes)")
        XCTAssertFalse(kept.paths.contains(folder.appendingPathComponent("LICENSE").path))
    }

    func testWhatCannotBeHonouredIsRefusedWhole() async throws {
        let folder = try Fixture.tally()
        let before = try String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8)
        let input = try JSONSerialization.data(withJSONObject: ["make": "readme", "sources": ["Nope"], "rounds": 9, "into": "/elsewhere",
                                                                "features": [String(repeating: "x", count: 300)], "directory": folder.path])
        do {
            _ = try await AnyAgentPackage(DocumentationAgent.self).perform(input)
            XCTFail("a call with four problems ran")
        } catch {
            let said = "\(error)"
            XCTAssertTrue(said.contains("4 problems, so nothing was written"), said)
            for reason in ["outside the project", "the source Nope does not exist", "`rounds` is 9", "at most 240 characters"] {
                XCTAssertTrue(said.contains(reason), "\(reason): \(said)")
            }
        }
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8), before)
    }
}
