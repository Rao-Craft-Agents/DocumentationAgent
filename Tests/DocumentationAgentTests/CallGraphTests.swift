import Foundation
import XCTest
@testable import DocumentationAgent

/// The call graph and its Granite flows: what each call reaches, and how sure the match is.
final class CallGraphTests: XCTestCase {
    private func graph(_ files: [String: String], modules: [String] = []) -> CallGraph {
        let sources = files.keys.sorted().map { SwiftSource(text: files[$0]!, path: $0, module: "App") }
        let graph = CallGraph(sources, modules: modules)
        graph.build()
        return graph
    }

    /// The edges out of the declaration `from` (by its qualified name), as `target qualified name: tier/via`.
    private func edges(_ graph: CallGraph, from: String) -> [String: String] {
        guard let g = graph.qualified.firstIndex(of: from) else { return [:] }
        var out: [String: String] = [:]
        for e in graph.edges where e.source == g { out[graph.qualified[e.target]] = e.via ?? CallGraph.tiers[e.tier] }
        return out
    }

    func testEachEdgeSaysHowSureItIs() {
        let graph = graph(["Sources/App/Pings.swift": """
            struct A { func ping(count: Int) {} }
            struct B {
                func ping(count: Int) {}
                func pong() {}
            }
            func use(items: [B], x: Unknown) {
                items.first?.pong()
                make().ping(count: 1)
                A().ping(count: 2)
                x.pong()
                print("pong")
            }
            """])
        let out = edges(graph, from: "use")
        XCTAssertEqual(out["B.pong"], "likely", "the name is unique, the receiver's type is not read")
        XCTAssertEqual(out["A.ping"], "exact", "the receiver is made of a type the code declares")
        XCTAssertEqual(out["B.ping"], "ambiguous", "two fit `make().ping(count:)`, and both are listed")
        XCTAssertEqual(graph.edges.filter { graph.qualified[$0.source] == "use" && graph.qualified[$0.target] == "A.ping" }.first?.tier, 0,
                       "a sure match beside an ambiguous one keeps the surer tier")
    }

    func testATypedReceiverReachesItsTypeAndAProtocolEveryConformer() throws {
        let model = ProjectModel(root: try Fixture.tally(), title: nil, sources: [], exclude: [])
        let graph = try XCTUnwrap(model.graph)
        let out = edges(graph, from: "Statement.today")
        XCTAssertEqual(out["SystemClock.now"], "protocol", "through the protocol, to its conformer")
        XCTAssertEqual(out["Clock.now"], "protocol", "and to the requirement")
        XCTAssertEqual(edges(graph, from: "BudgetService.Center.Load.reduce")["Budget.saved"], "exact")
    }

    func testOfSeveralTheCallersOwnModuleIsPreferred() {
        let graph = graph([
            "App/Root.swift": "struct Root { var body: some View { Home() } }",
            "App/Home.swift": "struct Home { init() {} }",
            "Packages/Demo/Home.swift": "struct Home { init() {} }",
        ], modules: ["Packages/Demo/"])
        let root = graph.qualified.firstIndex(of: "Root.body")!
        let targets = graph.edges.filter { $0.source == root }.map { graph.files[graph.fileOf[$0.target]].path }
        XCTAssertEqual(targets, ["App/Home.swift"], "the demo's Home is another module's")
    }

    func testTheGraniteFlowsOfAnApp() throws {
        let model = ProjectModel(root: try Fixture.tally(), title: nil, sources: [], exclude: [])
        let graph = try XCTUnwrap(model.graph)
        XCTAssertEqual(edges(graph, from: "TallyApp.init")["LedgerService.Boot.reduce"], "event", "a relay's center's event, sent")
        XCTAssertEqual(edges(graph, from: "LedgerService.Boot.reduce")["BudgetService.Center.Load.reduce"], "event",
                       "to a reducer declared in an extension of the center")
        let view = edges(graph, from: "Month.view")
        XCTAssertEqual(view["Month.Refresh.reduce"], "event", "a component's own center")
        XCTAssertEqual(view["LedgerService.Record.reduce"], "event", "a chain broken over lines reads as one")
        XCTAssertEqual(edges(graph, from: "Budget.fits")["LedgerService.has"], "relay", "a service's method, called through a parameter")
        XCTAssertNotNil(model.entry.map { graph.qualified[$0] == "TallyApp" }, "the @main type is the entry")
    }

    func testServicesAreRankedByWhatTheyReach() throws {
        let model = ProjectModel(root: try Fixture.tally(), title: nil, sources: [], exclude: [])
        XCTAssertEqual(model.services.map(\.name), ["BudgetService", "LedgerService"])
        XCTAssertEqual(model.services.map(\.rank), [0, 1])
        let ledger = model.services[1]
        XCTAssertEqual(ledger.reaches, ["BudgetService"])
        XCTAssertEqual(ledger.relays, ["BudgetService"], "the @Relay its reducer holds")
        XCTAssertEqual(ledger.events.map(\.event), ["boot", "record"])
        XCTAssertEqual(ledger.events.map(\.reducer), ["Boot", "Record"])
        XCTAssertEqual(ledger.events[0].doc, "Reads the ledger back and asks the budgets to load.")
        XCTAssertEqual(ledger.what, "The ledger: every entry of the month, how much each was, and what each budget has spent.")
        XCTAssertEqual(model.components.map(\.name), ["Month"])
        XCTAssertEqual(model.components[0].relays, ["LedgerService"])
        XCTAssertEqual(model.components[0].events.map(\.event), ["refresh"])
    }

    func testACircleOfRelaysIsCutAndSaid() {
        let graph = graph([
            "Services/AService/AService.swift": """
                struct AService: GraniteService {
                    @Relay var b: BService
                    func go() { b.go() }
                }
                """,
            "Services/BService/BService.swift": """
                struct BService: GraniteService {
                    @Relay var a: AService
                    func go() { a.go() }
                }
                """,
        ])
        let ranks = graph.granite.ranks()
        XCTAssertEqual(Set(ranks.map(\.name)), ["AService", "BService"])
        XCTAssertEqual(graph.granite.cycles, ["AService → BService → AService"])
    }

    func testCompilerDirectivesAndCaseLabelsAreNoCalls() {
        let graph = graph(["Sources/App/Pick.swift": """
            enum Kind { case photo(Int); case video }
            func photo(_ x: Int) {}
            func pick(_ kind: Kind) {
                #if os(iOS)
                switch kind {
                case .photo(let size): photo(size)
                case .video: break
                }
                #endif
            }
            """])
        let out = edges(graph, from: "pick")
        XCTAssertEqual(Array(out.keys), ["photo"], "the call in the case's body, not its pattern or the directive")
    }
}
