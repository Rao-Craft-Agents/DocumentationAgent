import Foundation
import GraniteAgents
import XCTest
@testable import DocumentationAgent

/// The Markdown docs: the architecture in dependency order, a page per top-level folder led by what its code says,
/// the glossary, how to build; each folder's overview the model's when it passes its checks.
final class MarkdownTests: XCTestCase {
    private func markdown(_ folder: URL, model: FakeHostModel? = nil, into: String? = nil) async throws -> DocumentationResult {
        var input: [String: Any] = ["make": "markdown", "directory": folder.path]
        if let into { input["into"] = into }
        let answer = try await AnyAgentPackage(DocumentationAgent.self).perform(try JSONSerialization.data(withJSONObject: input),
                                                                                 host: AgentHost(directory: folder.path, model: model))
        return try JSONDecoder().decode(DocumentationResult.self, from: answer)
    }

    private func read(_ folder: URL, _ name: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent("Docs/" + name), encoding: .utf8)
    }

    func testThePagesAreReadOffTheCode() async throws {
        let folder = try Fixture.tally()
        let result = try await markdown(folder)
        XCTAssertEqual(result.paths.map { ($0 as NSString).lastPathComponent }, ["Architecture.md", "Sources.md", "Tests.md", "Web.md", "Glossary.md", "Building.md"])
        XCTAssertEqual(result.path, folder.appendingPathComponent("Docs/Architecture.md").path)
        XCTAssertEqual(result.notes, ["the folders' overviews are left out: the host offers no model"])

        let architecture = try read(folder, "Architecture.md")
        XCTAssertTrue(architecture.hasPrefix("# Tally: architecture\n\nTally: a household ledger that keeps each month's spending beside the budgets it is held to. *(From [Package.swift](../Package.swift).)*"), architecture)
        XCTAssertTrue(architecture.contains("| [Tally](../Sources/Tally) | target | 0 | Granite |"), architecture)
        XCTAssertTrue(architecture.contains("| [Sources/](Sources.md) | 1 target: `Tally` | 15 | 203 |"), architecture)
        XCTAssertTrue(architecture.contains("### LedgerService\n\nRank 1, in [LedgerService.swift:6](../Sources/Tally/Services/LedgerService/LedgerService.swift#L6); it reaches `BudgetService`."), architecture)
        XCTAssertTrue(architecture.contains("| `boot` | [Boot](../Sources/Tally/Services/LedgerService/Reducers/LedgerService.Boot.swift#L5) | Reads the ledger back and asks the budgets to load. |"), architecture)
        XCTAssertTrue(architecture.contains("| `record` | [Record](../Sources/Tally/Services/LedgerService/Reducers/LedgerService.Record.swift#L4) | Writes `state.spent`. |"),
                      "a reducer with no doc comment says what its code does: \(architecture)")
        XCTAssertTrue(architecture.contains("## Calls\n\nRead by a lexer and a brace walk, not a compiler"))

        let sources = try read(folder, "Sources.md")
        XCTAssertTrue(sources.hasPrefix("# Sources\n\nIt holds 1 target: `Tally`. *(Read off its code: no root type says what this folder is"), sources)
        XCTAssertTrue(sources.contains("| [Tally/Services/LedgerService/LedgerService.swift](../Sources/Tally/Services/LedgerService/LedgerService.swift) | 13 | The ledger: every entry of the month, how much each was, and what each budget has spent. |"), sources)
        XCTAssertTrue(sources.contains("## Types\n\n- **`Budget`**, public struct in [Budget.swift:4](../Sources/Tally/Models/Budget.swift#L4): A budget the household keeps"), sources)

        let web = try read(folder, "Web.md")
        XCTAssertTrue(web.contains("| [chart.ts](../Web/chart.ts) | 4 | The month's chart, drawn in a web view: it posts the bar a person taps back to the app as JSON. |"), web)

        let glossary = try read(folder, "Glossary.md")
        XCTAssertTrue(glossary.contains("- **`LedgerService`**, struct in [LedgerService.swift:6](../Sources/Tally/Services/LedgerService/LedgerService.swift#L6): LedgerService is a Granite service; its center declares 2 events: `boot` and `record`, and it holds a relay to `BudgetService`."), glossary)
        XCTAssertTrue(glossary.contains("- **`SystemClock`**, struct in [Clock.swift:8](../Sources/Tally/Support/Clock.swift#L8): Conforms to `Clock`."), glossary)

        let building = try read(folder, "Building.md")
        XCTAssertTrue(building.contains("The package:\n\n```sh\nswift build\n```"), building)
        XCTAssertTrue(building.contains("The package's tests:\n\n```sh\nswift test\n```"), building)
        XCTAssertTrue(building.contains("| Granite | https://github.com/riteshpakala/Granite.git | branch main |"), building)
    }

    func testEachFolderHasTheModelsOverviewWhenItPasses() async throws {
        let folder = try Fixture.tally()
        // One answer for every folder: it cites a file only the Sources/ digest names, so Tests/ and Web/ refuse it.
        let answer = ReadmeTests.answer([("This folder holds the app's code: a ledger service, a budget service and the month that shows them.", [ReadmeTests.ledger])])
        let model = FakeHostModel([answer])
        let result = try await markdown(folder, model: model)
        let sources = try read(folder, "Sources.md")
        XCTAssertTrue(sources.contains("This folder holds the app's code: a ledger service, a budget service and the month that shows them ([LedgerService.swift](../Sources/Tally/Services/LedgerService/LedgerService.swift))."), sources)
        XCTAssertEqual(model.asked.count, 1 + 3 + 3, "Sources/ passes at once; Tests/ and Web/ are refused every round")
        XCTAssertEqual(result.notes.filter { $0.hasPrefix("Tests/'s overview is left out") || $0.hasPrefix("Web/'s overview is left out") }.count, 2, "\(result.notes)")
        XCTAssertTrue(model.asked[0].user.contains("Folder Sources/ of Tally"), model.asked[0].user)
        XCTAssertFalse(try read(folder, "Tests.md").contains("This folder holds the app's code"))
    }

    func testIntoMovesThePages() async throws {
        let folder = try Fixture.tally()
        let result = try await markdown(folder, into: "Documentation/Code")
        XCTAssertTrue(result.paths.allSatisfy { $0.hasPrefix(folder.appendingPathComponent("Documentation/Code").path + "/") }, "\(result.paths)")
        let architecture = try String(contentsOf: folder.appendingPathComponent("Documentation/Code/Architecture.md"), encoding: .utf8)
        XCTAssertTrue(architecture.contains("[Package.swift](../../Package.swift)"), "links climb out of the folder they are in")
    }
}
