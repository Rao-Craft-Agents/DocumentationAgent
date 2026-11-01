import Foundation
import XCTest
@testable import DocumentationAgent

/// The host's folder, kept as the host wrote it.
final class AgentFilesTests: XCTestCase {
    func testPathsKeepTheHostsFormAndResolveParents() {
        let files = AgentFiles(directory: "/private/tmp/app")
        XCTAssertEqual(files.resolve("Docs/site").path, "/private/tmp/app/Docs/site", "/private is not dropped")
        XCTAssertEqual(files.resolve("Docs/../Docs/./site/index.html").path, "/private/tmp/app/Docs/site/index.html")
        XCTAssertEqual(files.resolve("/abs/a/../b").path, "/abs/b")
        XCTAssertEqual(files.relative(files.resolve("Docs/site/data.js")), "Docs/site/data.js")
        XCTAssertEqual(files.relative(URL(fileURLWithPath: "/elsewhere/x")), "/elsewhere/x")
    }
}
