import Foundation
import GraniteAgents
import XCTest
@testable import DocumentationAgent

/// The site: the files it writes, the data its pages read, the same bytes on a second run, and an orb that never
/// carries a key.
final class SiteTests: XCTestCase {
    private func site(_ folder: URL, _ extra: [String: Any] = [:]) async throws -> DocumentationResult {
        var input: [String: Any] = ["make": "site", "directory": folder.path]
        input.merge(extra) { $1 }
        let answer = try await AnyAgentPackage(DocumentationAgent.self).perform(try JSONSerialization.data(withJSONObject: input))
        return try JSONDecoder().decode(DocumentationResult.self, from: answer)
    }

    /// The JSON a generated script assigns, read back.
    static func payload(_ url: URL) throws -> [String: Any] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let assignment = try XCTUnwrap(text.components(separatedBy: "\n").last { $0.hasPrefix("window.DOCS_SITE = ") || $0.hasPrefix("window.DOCS_EXPLORER.sources[") })
        let json = assignment[assignment.range(of: " = ")!.upperBound...].dropLast()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testTheSiteIsWrittenWithTheDataItsPagesRead() async throws {
        let folder = try Fixture.tally()
        let result = try await site(folder)
        let site = folder.appendingPathComponent("Docs/site")
        let names = result.paths.map { String($0.dropFirst(site.path.count + 1)) }
        XCTAssertEqual(names, ["index.html", "app.css", "core.js", "folders.js", "explorer.js", "app.js", "data.js", "explorer/index.js",
                               "explorer/root.js", "explorer/Sources.js", "explorer/Tests.js", "explorer/Web.js", ".gitignore"])
        let page = try String(contentsOf: site.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertTrue(page.contains("<title>Tally</title>"))
        XCTAssertFalse(page.contains("ask.js"), "no orb unless asked for")
        XCTAssertFalse(page.contains("{{"), "no template marker is left")
        XCTAssertEqual(try String(contentsOf: site.appendingPathComponent(".gitignore"), encoding: .utf8), "# The ask orb's key lives here, on this machine only.\nlocal/\n")

        let data = try Self.payload(site.appendingPathComponent("data.js"))
        let meta = try XCTUnwrap(data["meta"] as? [String: Any])
        XCTAssertEqual(meta["title"] as? String, "Tally")
        XCTAssertEqual(meta["site"] as? String, "Docs/site", "the page finds the project's folder from its own address")
        XCTAssertEqual(data["spine"] as? [String], ["Sources", "Tests", "Web"])
        let folders = try XCTUnwrap(data["folders"] as? [String: [String: Any]])
        let ledger = try XCTUnwrap(folders["Sources/Tally/Services/LedgerService"])
        XCTAssertEqual((ledger["about"] as? [String: Any])?["from"] as? String, "what")
        XCTAssertEqual((ledger["rootType"] as? [String: Any])?["path"] as? String, "Sources/Tally/Services/LedgerService/LedgerService.swift")
        XCTAssertEqual((folders["Sources"]?["holds"] as? String), "1 target: `Tally`")
        XCTAssertEqual((data["files"] as? [[String: Any]])?.count, 18)
        XCTAssertNotNil((data["docs"] as? [String: Any])?["README.md"], "every Markdown file is read on the site")
        XCTAssertEqual((data["services"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["BudgetService", "LedgerService"])
        XCTAssertEqual((data["trails"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["boot", "budgetservice", "ledgerservice"])
        let build = try XCTUnwrap(data["build"] as? [String: Any])
        XCTAssertEqual((build["build"] as? [[String: Any]])?.compactMap { $0["command"] as? String }, ["swift build"])

        let index = try Self.payload(site.appendingPathComponent("explorer/index.js"))
        XCTAssertEqual(index["modules"] as? [String], [".", "Sources", "Tests", "Web"])
        XCTAssertEqual((index["units"] as? [String: String])?["."], "root")
        let edges = try XCTUnwrap(index["edges"] as? [[Any]])
        XCTAssertTrue(edges.contains { $0.count == 6 && $0[5] as? String == "event" }, "the Granite flows are edges with their kind")
        let services = try XCTUnwrap(index["services"] as? [[String: Any]])
        XCTAssertEqual(services.map { $0["name"] as? String }, ["BudgetService", "LedgerService"])
        XCTAssertEqual((services[1]["events"] as? [[Any]])?.map { $0[0] as? String }, ["boot", "record"])
        let sources = try Self.payload(site.appendingPathComponent("explorer/Sources.js"))
        let files = try XCTUnwrap(sources["files"] as? [[String: Any]])
        let ledgerFile = try XCTUnwrap(files.first { $0["path"] as? String == "Sources/Tally/Services/LedgerService/LedgerService.swift" })
        XCTAssertEqual(ledgerFile["text"] as? String, Fixture.tallyFiles["Sources/Tally/Services/LedgerService/LedgerService.swift"], "the source, verbatim")
        let web = try Self.payload(site.appendingPathComponent("explorer/Web.js"))
        XCTAssertEqual(((web["files"] as? [[String: Any]])?.first?["lang"]) as? String, "TypeScript", "another language gets its page and its text")
    }

    func testTheSameTreeWritesTheSameBytes() async throws {
        let folder = try Fixture.tally()
        let first = try await site(folder, ["ask": true])
        let bytes = try first.paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let second = try await site(folder, ["ask": true])
        XCTAssertEqual(second.paths, first.paths)
        XCTAssertEqual(try second.paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, bytes, "a rerun reads the same tree, never its own output")
    }

    func testTheOrbIsCarriedOnlyWhenAskedAndNeverWithAKey() async throws {
        let folder = try Fixture.tally()
        let result = try await site(folder, ["ask": true])
        let siteFolder = folder.appendingPathComponent("Docs/site")
        XCTAssertTrue(result.paths.contains(siteFolder.appendingPathComponent("ask.js").path))
        XCTAssertTrue(try String(contentsOf: siteFolder.appendingPathComponent("index.html"), encoding: .utf8).contains("<script src=\"ask.js\"></script>"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: siteFolder.appendingPathComponent("local").path), "the key's folder is the person's to make")
        XCTAssertTrue(result.notes.contains { $0.contains("local/ask.js; none was written") }, "\(result.notes)")
        for path in result.paths {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertNil(text.range(of: #"(?i)(api[_-]?key|bearer)\s*[:=]\s*["'][A-Za-z0-9_\-]{16,}"#, options: .regularExpression), "no key in \(path)")
        }
        // Asked for again without the orb, the site drops the script it no longer loads.
        let again = try await site(folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: siteFolder.appendingPathComponent("ask.js").path))
        XCTAssertTrue(again.notes.contains { $0.contains("ask.js") }, "\(again.notes)")
    }

    func testAFileOverTheLimitIsLeftOutAndSaid() async throws {
        let folder = try Fixture.tally()
        try Fixture.write(["Sources/Tally/Generated/Blob.swift": "let blob = \"" + String(repeating: "x", count: 500_000) + "\"\n"], into: folder)
        let result = try await site(folder)
        XCTAssertTrue(result.notes.contains { $0.hasPrefix("1 file was left out, the first Sources/Tally/Generated/Blob.swift: it is 500 KB") }, "\(result.notes)")
        let data = try Self.payload(folder.appendingPathComponent("Docs/site/data.js"))
        XCTAssertEqual(((data["meta"] as? [String: Any])?["skipped"] as? [[String]])?.first?.first, "Sources/Tally/Generated/Blob.swift")
        let index = try Self.payload(folder.appendingPathComponent("Docs/site/explorer/index.js"))
        XCTAssertFalse((index["files"] as? [[String: Any]] ?? []).contains { $0["path"] as? String == "Sources/Tally/Generated/Blob.swift" })
    }

    func testAnEarlierSitesStaleScriptIsRemovedAndAnOldSiteIsNeverRead() async throws {
        let folder = try Fixture.tally()
        _ = try await site(folder)
        let stale = folder.appendingPathComponent("Docs/site/explorer/Old.js")
        try (SiteData.header + "window.DOCS_EXPLORER.sources[\"Old\"] = {};\n").write(to: stale, atomically: true, encoding: .utf8)
        // A copy of the site elsewhere in the project is a site, not code to document.
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder.appendingPathComponent("Docs/site"), to: folder.appendingPathComponent("Archive/site"))
        let result = try await site(folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(result.notes.contains { $0.contains("Old.js") }, "\(result.notes)")
        XCTAssertEqual(result.files, 18, "the copied site's scripts are not read as the project's code")
    }

    func testAnIntoOutsideTheProjectIsRefused() async throws {
        let folder = try Fixture.tally()
        do {
            _ = try await site(folder, ["into": "../elsewhere"])
            XCTFail("a site was written outside the project")
        } catch {
            XCTAssertTrue("\(error)".contains("outside the project"), "\(error)")
        }
    }
}
