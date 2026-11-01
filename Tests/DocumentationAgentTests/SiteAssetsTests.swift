import Foundation
import XCTest
@testable import DocumentationAgent

/// The site's front end, carried as Swift literals: each one the file in `site-src/` it was made from, so an edit of
/// the page is never lost and never half-shipped. Run `python3 -I scripts/embed-site.py` after editing `site-src/`.
final class SiteAssetsTests: XCTestCase {
    static let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("site-src")

    func testEveryLiteralIsItsFile() throws {
        let pairs: [(String, String)] = [("index.html", SiteAssets.index), ("app.css", SiteAssets.css), ("core.js", SiteAssets.core),
                                         ("folders.js", SiteAssets.folders), ("explorer.js", SiteAssets.explorer), ("ask.js", SiteAssets.ask),
                                         ("app.js", SiteAssets.app)]
        for (name, literal) in pairs {
            let file = try String(contentsOf: Self.source.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(literal, file, "site-src/\(name) and its literal differ: run python3 -I scripts/embed-site.py")
        }
        let shipped = try FileManager.default.contentsOfDirectory(atPath: Self.source.path).filter { !$0.hasPrefix(".") }.sorted()
        XCTAssertEqual(shipped, pairs.map(\.0).sorted(), "every file in site-src/ is carried")
    }

    func testThePageIsTitledAndCarriesTheOrbOnlyWhenAsked() {
        let page = SiteAssets.page(title: "Tally & <Co>", ask: false)
        XCTAssertTrue(page.contains("<title>Tally &amp; &lt;Co&gt;</title>"))
        XCTAssertFalse(page.contains("ask.js"))
        XCTAssertFalse(page.contains("<!--ask-->"))
        XCTAssertTrue(SiteAssets.page(title: "Tally", ask: true).contains("<script src=\"ask.js\"></script>\n<script src=\"app.js\"></script>"))
        XCTAssertEqual(SiteAssets.files(ask: false).map(\.name), ["app.css", "core.js", "folders.js", "explorer.js", "app.js"])
    }

    /// Every script parses, when this Mac has Node to say so.
    func testEveryScriptParses() throws {
        let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipIf(node == nil, "no node on this Mac")
        for name in ["core.js", "folders.js", "explorer.js", "ask.js", "app.js"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: node!)
            process.arguments = ["--check", Self.source.appendingPathComponent(name).path]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let said = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(name): \(said)")
        }
    }
}
