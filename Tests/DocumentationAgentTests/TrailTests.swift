import Foundation
import GraniteAgents
import XCTest
@testable import DocumentationAgent

/// The trails: the person's lines read and resolved, every bad step refused at once, and the walks the Granite flows
/// give when the call names none.
final class TrailTests: XCTestCase {
    private func builder() throws -> (TrailBuilder, ProjectModel) {
        let model = ProjectModel(root: try Fixture.tally(), title: nil, sources: [], exclude: [])
        return (TrailBuilder(graph: try XCTUnwrap(model.graph), model: model), model)
    }

    func testALineIsANameAndArrowedSteps() {
        XCTAssertEqual(try TrailLine.parse("close a month: Statement.today -> Budget.fits → LedgerService.Record").get(),
                       TrailLine(name: "close a month", steps: ["Statement.today", "Budget.fits", "LedgerService.Record"]))
        let refused: [(String, String)] = [
            ("Statement.today → Budget.fits", "no colon"),
            ("walk: Statement.today", "one step"),
            ("walk: Statement.today →  → Budget.fits", "empty step"),
            (": A.b → C.d", "names no trail"),
            ("long: " + (1...15).map { "S\($0).run" }.joined(separator: " → "), "split it in two"),
        ]
        for (line, reason) in refused {
            guard case .failure(let error) = TrailLine.parse(line) else { XCTFail(line); continue }
            XCTAssertTrue(error.description.contains(reason), "\(line) → \(error)")
        }
    }

    func testAStepResolvesToWhatItNames() throws {
        let (trails, model) = try builder()
        let graph = try XCTUnwrap(model.graph)
        func names(_ step: String) throws -> [String] { try trails.resolve(step).get().map { graph.qualified[$0] } }
        XCTAssertEqual(try names("LedgerService.Boot"), ["LedgerService.Boot.reduce"], "a reducer walks as its reduce")
        XCTAssertEqual(try names("TallyApp.init"), ["TallyApp.init"])
        XCTAssertEqual(try names("Budget.fits(_:)"), ["Budget.fits"])
        XCTAssertEqual(try names("today"), ["Statement.today"], "a bare name the project has once")
        XCTAssertEqual(try names("Clock"), ["Clock"])
        guard case .failure(let missing) = trails.resolve("Ledger.close") else { return XCTFail("a step that names nothing resolved") }
        XCTAssertTrue(missing.description.contains("names no declaration"), missing.description)
        XCTAssertEqual(try names("now"), ["SystemClock.now"], "the implementation, not the requirement with no body")
        guard case .failure(let several) = trails.resolve("reduce") else { return XCTFail("an ambiguous step resolved") }
        XCTAssertTrue(several.description.contains("names 4 declarations"), several.description)
        XCTAssertTrue(several.description.contains("add the argument labels or the type"), several.description)
    }

    func testTheCallsTrailsAreWalkedWithTheirHops() throws {
        let (builder, _) = try builder()
        let made = builder.trails(from: ["boot the month: TallyApp.init → LedgerService.Boot → BudgetService.Center.Load"])
        XCTAssertEqual(made.reasons, [])
        let trail = try XCTUnwrap(made.trails.first)
        XCTAssertEqual(trail.id, "boot-the-month")
        XCTAssertEqual(trail.steps.map(\.title), ["TallyApp.init", "LedgerService.Boot", "BudgetService.Center.Load"])
        XCTAssertNil(trail.steps[0].entries[0].hop)
        XCTAssertEqual(trail.steps[1].entries[0].hop?.kind, "event")
        XCTAssertEqual(trail.steps[2].entries[0].hop?.kind, "event")
        XCTAssertEqual(trail.steps[2].entries[0].hop?.step, 2, "reached from the entry before it")
        XCTAssertEqual(trail.steps[1].entries[0].note, "Reads the ledger back and asks the budgets to load.", "a reducer's note is its doc comment")
        XCTAssertEqual(trail.steps[1].entries[0].cite, "doc")
        let bad = builder.trails(from: ["broken: Ledger.close → Statement.today", "short: Statement.today"])
        XCTAssertEqual(bad.reasons.count, 2, "every problem at once: \(bad.reasons)")
    }

    func testWithNoLinesTheFlowsGiveBootThenEachService() throws {
        let (builder, _) = try builder()
        let trails = builder.derived()
        XCTAssertEqual(trails.map(\.title), ["Boot", "BudgetService", "LedgerService"])
        let boot = trails[0]
        XCTAssertEqual(boot.steps.map(\.title), ["TallyApp.init", "TallyApp.body", "LedgerService.Boot", "BudgetService.Center.Load"])
        XCTAssertNil(boot.steps[1].entries[0].hop, "the body is a start of its own: the system calls it")
        XCTAssertEqual(boot.steps[3].entries[0].hop?.kind, "event")
        XCTAssertTrue(boot.steps[0].entries[0].note.contains("sets off `LedgerService.Boot` (event)"), boot.steps[0].entries[0].note)
        XCTAssertEqual(trails[2].steps.map(\.title), ["boot → Boot", "record → Record"])
        XCTAssertTrue(trails[2].steps[1].entries[0].note.contains("writes `state.spent`"), trails[2].steps[1].entries[0].note)
        XCTAssertEqual(trails[2].steps[1].entries[0].hop?.kind, "sent", "an event is sent from elsewhere")
        XCTAssertEqual(Set(trails.map(\.mark)).count, trails.count, "a mark a trail")
    }

    func testABadTrailIsRefusedAndNothingIsWritten() async throws {
        let folder = try Fixture.tally()
        let input = try JSONSerialization.data(withJSONObject: ["make": "site", "trails": ["walk: Ledger.close → Statement.today"], "directory": folder.path])
        do {
            _ = try await AnyAgentPackage(DocumentationAgent.self).perform(input)
            XCTFail("a trail that names nothing was walked")
        } catch {
            XCTAssertTrue("\(error)".contains("`Ledger.close` names no declaration"), "\(error)")
            XCTAssertTrue("\(error)".contains("nothing was written"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Docs").path))
    }
}
