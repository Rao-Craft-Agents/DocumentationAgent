import Foundation
import GraniteAgents
import XCTest
@testable import DocumentationAgent

/// The three makes on real code, and the site opened in a real browser. Gated (`DOCS_BUILD=1`): a copy of Loom
/// (`/Users/ritesh/Documents/repositories/Loom`, never written to) and a copy of this repository are documented every
/// way, the site on Loom is timed, and every kind of route of each site is drawn in headless Chrome from `file://`:
/// a route that logs anything to the console fails, and the Explorer must list Loom's services with their events.
final class DocumentationBuildTests: XCTestCase {
    static let loom = "/Users/ritesh/Documents/repositories/Loom"
    static let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DOCS_BUILD"] == "1", "set DOCS_BUILD=1 to document Loom and this package and open the sites")
    }

    func testAllThreeMakesOnACopyOfLoom() async throws {
        let original = try Data(contentsOf: URL(fileURLWithPath: Self.loom + "/README.md"))
        let copy = try Fixture.folder().appendingPathComponent("Loom")
        try Self.run("/bin/cp", ["-R", Self.loom, copy.path])

        let readme = try await Self.make("readme", in: copy)
        let text = try String(contentsOf: copy.appendingPathComponent("README.md"), encoding: .utf8)
        for said in ["# Loom", "## Requirements", "-scheme \"Loom (iOS)\" -destination 'generic/platform=iOS Simulator' build", "## Structure",
                     "| [AccountService](Services/AccountService/AccountService.swift) | 1 |", "## License\n\nMIT: see [LICENSE](LICENSE)."] {
            XCTAssertTrue(text.contains(said), "Loom's README says \(said)")
        }
        XCTAssertEqual(readme.notes.first, "the README's opening paragraph and feature list are left out: the host offers no model")

        let markdown = try await Self.make("markdown", in: copy)
        XCTAssertEqual(Set(markdown.paths.map { ($0 as NSString).lastPathComponent }).isSuperset(of: ["Architecture.md", "Services.md", "Components.md", "Glossary.md", "Building.md"]), true)
        let architecture = try String(contentsOf: copy.appendingPathComponent("Docs/Architecture.md"), encoding: .utf8)
        XCTAssertTrue(architecture.contains("| 2 | Loom | the app, Loom.xcodeproj |"), "the app sits above the packages it imports")

        let started = Date()
        let site = try await Self.make("site", in: copy)
        let seconds = Date().timeIntervalSince(started)
        print(String(format: "docs: the site on Loom (%d files, %d Swift) took %.1f s", site.files, site.swift, seconds))
        XCTAssertLessThan(seconds, 30, "the site on Loom builds well under a minute")
        XCTAssertEqual(site.services, 10)
        XCTAssertEqual(site.trails.first, "Boot")

        let pages = try Self.open(copy.appendingPathComponent("Docs/site"), routes: [
            "/", "/Services", "/Services/AccountService/AccountService.swift:12", "/explorer", "/trail/boot/2", "/find/AccountService.Boot", "/file/README.md",
        ])
        XCTAssertTrue(pages["/"]!.contains("<h1 class=\"view-title\">Loom</h1>"))
        XCTAssertTrue(pages["/Services"]!.contains("It holds 10 Granite services"))
        XCTAssertTrue(pages["/Services/AccountService/AccountService.swift:12"]!.contains("class=\"xp-path\">Services/AccountService/AccountService.swift<"))
        XCTAssertTrue(pages["/Services/AccountService/AccountService.swift:12"]!.contains("id=\"L12\""))
        let explorer = pages["/explorer"]!
        for service in ["AccountService", "AnalyzeService", "BookmarkService", "ConfigService", "ContentService", "DraftService", "ExplorerService",
                        "LayoutService", "LoomService", "ModalService"] {
            XCTAssertTrue(explorer.contains("data-service=\"\(service)\""), "the Explorer lists \(service)")
        }
        for event in ["boot → Boot", "auth → Auth", "restart → Restart", "interact → Interact", "summarize → Summarize"] {
            XCTAssertTrue(explorer.contains(event), "the Explorer lists the event \(event)")
        }
        XCTAssertTrue(pages["/trail/boot/2"]!.contains("data-trail=\"boot\""))
        XCTAssertTrue(pages["/find/AccountService.Boot"]!.contains("id=\"xp-opt-0\""))
        XCTAssertTrue(pages["/file/README.md"]!.contains("class=\"prose doc-page\""))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: Self.loom + "/README.md")), original, "Loom itself is never written")
    }

    func testAllThreeMakesOnThisRepository() async throws {
        let copy = try Fixture.folder().appendingPathComponent("DocumentationAgent")
        try Self.run("/usr/bin/rsync", ["-a", "--exclude", ".build", "--exclude", ".swiftpm", Self.repository.path + "/", copy.path + "/"])
        let readme = try await Self.make("readme", in: copy)
        XCTAssertTrue(try String(contentsOf: copy.appendingPathComponent("README.md"), encoding: .utf8).contains("# DocumentationAgent"))
        XCTAssertTrue(readme.paths.allSatisfy { $0.hasPrefix(copy.path) })
        let markdown = try await Self.make("markdown", in: copy)
        XCTAssertTrue(markdown.paths.contains(copy.appendingPathComponent("Docs/Sources.md").path))
        let site = try await Self.make("site", in: copy, extra: ["ask": true, "trails": [
            "a call: DocumentationAgent.run → DocumentationRun.run → ProjectModel.init → CallGraph.build",
        ]])
        XCTAssertEqual(site.trails, ["a call"])
        let pages = try Self.open(copy.appendingPathComponent("Docs/site"), routes: [
            "/", "/Sources/DocumentationAgent/Graph", "/Sources/DocumentationAgent/Graph/CallGraph.swift:40", "/explorer", "/trail/a-call/3",
            "/find/CallGraph.build", "/file/README.md",
        ])
        XCTAssertTrue(pages["/Sources/DocumentationAgent/Graph"]!.contains("<h1 class=\"view-title\">Graph</h1>"))
        XCTAssertTrue(pages["/trail/a-call/3"]!.contains("ProjectModel.init(root:title:sources:exclude:)"))
        XCTAssertTrue(pages["/file/README.md"]!.contains("class=\"prose doc-page\""))
    }

    /// Code in other languages gets folder and file pages and search, and no call graph; its site draws as cleanly.
    func testASiteForCodeWithNoSwift() async throws {
        let folder = try Fixture.folder()
        try Fixture.write([
            "package.json": #"{"name": "tide-tables", "description": "Tide tables for a harbour", "scripts": {"build": "tsc", "test": "vitest"}}"#,
            "src/tides.ts": "// Tides: the next high and low water for a harbour, from its constants.\nexport function next(harbour: string) {\n  return harbour;\n}\n",
            "src/chart/draw.ts": "/** Draws a day of tides as a curve. */\nexport function draw() {}\n",
            "scripts/fetch.py": "\"\"\"Fetches a harbour's constants from the almanac.\"\"\"\n\ndef fetch(name):\n    return name\n",
            "docs/Harbours.md": "# Harbours\n\nEach harbour has its own [constants](../src/tides.ts).\n",
        ], into: folder)
        let readme = try await Self.make("readme", in: folder)
        let text = try String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("# tide-tables") && text.contains("npm run build") && text.contains("npm test"), text)
        XCTAssertEqual(readme.swift, 0)
        let site = try await Self.make("site", in: folder)
        XCTAssertEqual(site.trails, [])
        XCTAssertTrue(site.notes.contains("no call graph and no trail: the project has no Swift to walk; its files have pages and search"), "\(site.notes)")
        let pages = try Self.open(folder.appendingPathComponent("Docs/site"), routes: ["/", "/src", "/src/tides.ts:2", "/explorer", "/find/harbour", "/file/docs/Harbours.md"])
        XCTAssertTrue(pages["/src/tides.ts:2"]!.contains("class=\"xp-path\">src/tides.ts<"))
        XCTAssertTrue(pages["/src"]!.contains("Tides: the next high and low water for a harbour, from its constants."))
        XCTAssertTrue(pages["/file/docs/Harbours.md"]!.contains("href=\"#/src/tides.ts\""), "a doc's link to a file opens the file's page")
    }

    // MARK: - Helpers

    static func make(_ make: String, in folder: URL, extra: [String: Any] = [:]) async throws -> DocumentationResult {
        var input: [String: Any] = ["make": make]
        input.merge(extra) { $1 }
        let answer = try await AnyAgentPackage(DocumentationAgent.self).perform(try JSONSerialization.data(withJSONObject: input),
                                                                                 host: AgentHost(directory: folder.path))
        return try JSONDecoder().decode(DocumentationResult.self, from: answer)
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw NSError(domain: "build", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text]) }
        return text
    }

    /// Each route drawn by headless Chrome from `file://`, its DOM by route; a route whose page logs to the console
    /// fails the test.
    static func open(_ site: URL, routes: [String]) throws -> [String: String] {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: chrome), "Google Chrome is not installed")
        let profile = try Fixture.folder()
        var pages: [String: String] = [:]
        for route in routes {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: chrome)
            process.arguments = ["--headless", "--disable-gpu", "--no-first-run", "--user-data-dir=" + profile.path, "--virtual-time-budget=10000",
                                 "--enable-logging=stderr", "--v=0", "--dump-dom", site.appendingPathComponent("index.html").absoluteString + "#" + route]
            let out = Pipe(), errors = Pipe()
            process.standardOutput = out
            process.standardError = errors
            try process.run()
            // The log is read beside the page, so neither pipe fills while the other is read.
            let log = LogReader(errors.fileHandleForReading)
            let dom = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let console = log.text().split(separator: "\n").filter { $0.contains(":CONSOLE") }
            XCTAssertEqual(console.count, 0, "\(route) logs to the console:\n" + console.joined(separator: "\n"))
            XCTAssertFalse(dom.contains("class=\"banner bad\""), "\(route) could not be drawn")
            XCTAssertGreaterThan(dom.count, 2_000, "\(route) drew nothing")
            print("docs: \(route) drew \(dom.count) bytes, \(console.count) console lines")
            pages[route] = dom
        }
        return pages
    }
}
