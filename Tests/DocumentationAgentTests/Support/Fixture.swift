import Foundation

enum Fixture {
    /// A folder of its own for one test, removed with the process's temporary files.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("docs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `files` (path from the folder → text) into `folder`.
    static func write(_ files: [String: String], into folder: URL) throws {
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A household ledger, Granite-shaped: what the package is held to documenting well. Another domain than the
    /// prompts' worked example (a recipe app), so an answer that copies the example is caught. An app with an entry,
    /// two services that relay and send events, a component with a center of its own, models with doc comments, a
    /// protocol and a conformer, a test, a TypeScript file and a README.
    static func tally() throws -> URL {
        let folder = try folder()
        try write(tallyFiles, into: folder)
        return folder
    }

    static let tallyFiles: [String: String] = [
        "Package.swift": """
            // swift-tools-version:6.0
            // Tally: a household ledger that keeps each month's spending beside the budgets it is held to.

            import PackageDescription

            let package = Package(
                name: "Tally",
                platforms: [.iOS(.v17), .macOS(.v14)],
                products: [
                    .library(name: "Tally", targets: ["Tally"]),
                ],
                dependencies: [
                    .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
                ],
                targets: [
                    .target(name: "Tally", dependencies: [.product(name: "Granite", package: "Granite")]),
                    .testTarget(name: "TallyTests", dependencies: ["Tally"]),
                ]
            )
            """,
        "README.md": """
            # Tally

            Tally keeps a household's spending beside the budgets it is held to, month by month, on iPhone and Mac.

            ## Building

            Run `swift build`, or open the package in Xcode.
            """,
        "LICENSE": "MIT License\n\nCopyright (c) 2026 Tally\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\n",
        "Sources/Tally/TallyApp.swift": """
            import SwiftUI
            import Granite

            /// The app: one window with the month, and the ledger booted before it shows.
            @main
            struct TallyApp: App {
                @Relay var ledger: LedgerService

                init() {
                    ledger.center.boot.send()
                }

                var body: some Scene {
                    WindowGroup {
                        Month()
                    }
                }
            }
            """,
        "Sources/Tally/Services/LedgerService/LedgerService.swift": """
            //  WHAT: The ledger: every entry of the month, how much each was, and what each budget has spent.
            //  PIN:  ONE WRITER. Only the ledger's reducers change the entries.

            import Granite

            struct LedgerService: GraniteService {
                @Service(.online) var center: Center

                /// Whether the month holds an entry named `name` of at least `amount`.
                func has(_ name: String, amount: Int) -> Bool {
                    state.entries.contains { $0.name == name && $0.amount >= amount }
                }
            }
            """,
        "Sources/Tally/Services/LedgerService/LedgerService+Center.swift": """
            import Granite

            extension LedgerService {
                struct Center: GraniteCenter {
                    struct State: GraniteState {
                        var entries: [Entry] = []
                        var spent: [String: Int] = [:]
                    }

                    @Event var boot: Boot.Reducer
                    @Event(debounce: 0.25) var record: Record.Reducer
                    @Store(persist: "tally.ledger") public var state: State
                }
            }
            """,
        "Sources/Tally/Services/LedgerService/Reducers/LedgerService.Boot.swift": """
            import Granite

            extension LedgerService {
                /// Reads the ledger back and asks the budgets to load.
                struct Boot: GraniteReducer {
                    typealias Center = LedgerService.Center

                    @Relay var budgets: BudgetService

                    func reduce(state: inout Center.State) {
                        state.spent = [:]
                        budgets.center.load.send()
                    }
                }
            }
            """,
        "Sources/Tally/Services/LedgerService/Reducers/LedgerService.Record.swift": """
            import Granite

            extension LedgerService {
                struct Record: GraniteReducer {
                    typealias Center = LedgerService.Center

                    struct Meta: GranitePayload {
                        var name: String
                        var amount: Int
                    }

                    @Payload var meta: Meta?

                    func reduce(state: inout Center.State) {
                        guard let meta else { return }
                        state.spent[meta.name, default: 0] += meta.amount
                    }
                }
            }
            """,
        "Sources/Tally/Services/BudgetService/BudgetService.swift": """
            import Granite

            /// Every budget the household keeps, and the months they cover.
            struct BudgetService: GraniteService {
                @Service var center: Center
            }
            """,
        "Sources/Tally/Services/BudgetService/BudgetService+Center.swift": """
            import Granite

            extension BudgetService {
                struct Center: GraniteCenter {
                    struct State: GraniteState {
                        var budgets: [Budget] = []
                    }

                    @Event var load: Load.Reducer
                    @Store public var state: State
                }
            }
            """,
        "Sources/Tally/Services/BudgetService/Reducers/BudgetService.Load.swift": """
            import Granite

            extension BudgetService.Center {
                struct Load: GraniteReducer {
                    typealias Center = BudgetService.Center

                    func reduce(state: inout Center.State) {
                        state.budgets = Budget.saved()
                    }
                }
            }
            """,
        "Sources/Tally/Components/Month/Month.swift": """
            import Granite
            import SwiftUI

            /// The month: what the ledger holds, entry by entry.
            struct Month: GraniteComponent {
                @Command var center: Center
                @Relay var ledger: LedgerService
            }
            """,
        "Sources/Tally/Components/Month/Month+Center.swift": """
            import Granite

            extension Month {
                struct Center: GraniteCenter {
                    struct State: GraniteState {
                        var filter: String = ""
                    }

                    @Event var refresh: Refresh.Reducer
                    @Store public var state: State
                }
            }
            """,
        "Sources/Tally/Components/Month/Month+View.swift": """
            import Granite
            import SwiftUI

            extension Month {
                var view: some View {
                    VStack {
                        Button("Refresh") {
                            center.refresh.send()
                        }
                        Button("Record the rent") {
                            ledger
                                .center
                                .record
                                .send(LedgerService.Record.Meta(name: "rent", amount: 1200))
                        }
                    }
                    .padding()
                }
            }
            """,
        "Sources/Tally/Components/Month/Reducers/Month.Refresh.swift": """
            import Granite

            extension Month {
                struct Refresh: GraniteReducer {
                    typealias Center = Month.Center

                    func reduce(state: inout Center.State) {
                        state.filter = ""
                    }
                }
            }
            """,
        "Sources/Tally/Models/Entry.swift": """
            import Foundation

            /// An entry of the month: what was spent, and how much.
            struct Entry: Codable, Hashable, Identifiable {
                var id: String { name }
                var name: String
                var amount: Int
            }
            """,
        "Sources/Tally/Models/Budget.swift": """
            import Foundation

            /// A budget the household keeps: how much each kind of spending may take in a month.
            public struct Budget: Codable, Hashable {
                public var title: String
                public var limits: [String: Int]
                public var month: Int

                /// The budgets saved on this device.
                static func saved() -> [Budget] {
                    []
                }

                /// Whether `ledger` holds every entry the budget allows for.
                func fits(_ ledger: LedgerService) -> Bool {
                    limits.allSatisfy { ledger.has($0.key, amount: $0.value) }
                }
            }
            """,
        "Sources/Tally/Support/Clock.swift": """
            import Foundation

            /// What tells the time, so a test can hold it still.
            protocol Clock {
                func now() -> Date
            }

            struct SystemClock: Clock {
                func now() -> Date { Date() }
            }

            struct Statement {
                let clock: Clock

                /// The day a statement closes: today, by the clock.
                func today() -> Date {
                    clock.now()
                }
            }
            """,
        "Tests/TallyTests/LedgerTests.swift": """
            import XCTest
            @testable import Tally

            final class LedgerTests: XCTestCase {
                func testNoBudgetsAreSavedAtFirst() {
                    XCTAssertTrue(Budget.saved().isEmpty)
                }
            }
            """,
        "Web/chart.ts": """
            // The month's chart, drawn in a web view: it posts the bar a person taps back to the app as JSON.
            export function tapped(bar: { name: string }) {
              window.webkit?.messageHandlers.chart.postMessage(JSON.stringify(bar));
            }
            """,
    ]
}
