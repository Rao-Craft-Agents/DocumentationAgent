import Foundation
import GraniteAgents
import XCTest
@testable import DocumentationAgent

/// The package as an app finds it: by its record, with the schema a model is shown and the guide a host prompts with.
final class DocumentationAgentTests: XCTestCase {
    func testTheRecordIsFoundWithNothingListed() throws {
        let docs = try XCTUnwrap(GraniteRoster.discovered().package("docs"), "the record is in this test binary")
        XCTAssertEqual(docs.module, "DocumentationAgent")
        XCTAssertEqual(docs.summary, DocumentationAgent.summary)
    }

    func testTheSchemaIsWhatAModelIsShown() {
        let docs = AnyAgentPackage(DocumentationAgent.self)
        XCTAssertEqual(docs.schema, .object([
            .init(name: "make", schema: .choice(["readme", "markdown", "site"]), required: true),
            .init(name: "into", schema: .string, required: false),
            .init(name: "sources", schema: .array(.string), required: false),
            .init(name: "title", schema: .string, required: false),
            .init(name: "tagline", schema: .string, required: false),
            .init(name: "features", schema: .array(.string), required: false),
            .init(name: "license", schema: .choice(["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"]), required: false),
            .init(name: "trails", schema: .array(.string), required: false),
            .init(name: "ask", schema: .boolean, required: false),
            .init(name: "rounds", schema: .integer, required: false),
            .init(name: "directory", schema: .string, required: false),
        ]))
        XCTAssertTrue(docs.takesDirectory)
        XCTAssertEqual(Set(docs.fields.keys), ["make", "into", "sources", "title", "tagline", "features", "license", "trails", "ask", "rounds"],
                       "a note beside every field the model sees, and none for the host's folder")
        XCTAssertNotNil(DocumentationAgent.word.range(of: #"^[a-z][a-z0-9]{1,31}$"#, options: .regularExpression), "a store-safe word")
        XCTAssertEqual(docs.lanes, 2)
    }

    func testTheGuideTeachesEachMakeWithACall() {
        let guide = AnyAgentPackage(DocumentationAgent.self).guide
        for word in ["`readme`", "`markdown`", "`site`", #"{"make": "readme""#, #"{"make": "markdown""#, #"{"make": "site""#, "`sources`",
                     "`into`", "`trails`", "→", "`features`", "`ask`", "local/ask.js", "no key is ever written", "Without a model"] {
            XCTAssertTrue(guide.contains(word), "the guide says \(word)")
        }
        XCTAssertFalse(guide.lowercased().contains("loom"), "the guide's examples are another app's")
    }

    /// The call as a host makes it: JSON in, the host's folder filled, JSON out naming the files.
    func testACallThroughTheRosterWritesTheFilesItNames() async throws {
        let folder = try Fixture.tally()
        let input = try JSONSerialization.data(withJSONObject: ["make": "site", "directory": folder.path])
        let notes = NoteBox()
        let answer = try await AnyAgentPackage(DocumentationAgent.self).perform(input, host: AgentHost(directory: folder.path, ask: "document this", note: { notes.append($0) }))
        let result = try JSONDecoder().decode(DocumentationResult.self, from: answer)
        XCTAssertEqual(result.make, "site")
        XCTAssertEqual(result.path, folder.appendingPathComponent("Docs/site/index.html").path)
        XCTAssertEqual(result.open, URL(fileURLWithPath: result.path!).absoluteString)
        for name in ["index.html", "app.css", "core.js", "folders.js", "explorer.js", "app.js", "data.js", "explorer/index.js", ".gitignore"] {
            XCTAssertTrue(result.paths.contains(folder.appendingPathComponent("Docs/site/" + name).path), "it names \(name)")
        }
        for path in result.paths {
            XCTAssertTrue(path.hasPrefix(folder.path + "/"), path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
        XCTAssertEqual(result.files, 18, "17 Swift files and a TypeScript one")
        XCTAssertEqual(result.swift, 17)
        XCTAssertEqual(result.services, 2)
        XCTAssertEqual(result.trails, ["Boot", "BudgetService", "LedgerService"], "boot, then the services lowest rank first")
        XCTAssertTrue(result.notes.isEmpty, "\(result.notes)")
        XCTAssertTrue(notes.lines.contains { $0.hasPrefix("read 18 files of code (17 Swift") }, "\(notes.lines)")
        XCTAssertTrue(notes.lines.contains { $0.hasPrefix("wrote") }, "\(notes.lines)")
    }

    /// A host on the wire may give the folder only in its AgentHost: every file still lands under it.
    func testWithNoDirectoryInTheCallTheHostsFolderIsUsed() async throws {
        let folder = try Fixture.tally()
        for make in ["readme", "markdown", "site"] {
            let input = try JSONSerialization.data(withJSONObject: ["make": make])
            let answer = try await AnyAgentPackage(DocumentationAgent.self).perform(input, host: AgentHost(directory: folder.path))
            let result = try JSONDecoder().decode(DocumentationResult.self, from: answer)
            XCTAssertFalse(result.paths.isEmpty, make)
            for path in result.paths {
                XCTAssertTrue(path.hasPrefix(folder.path + "/"), "\(make) wrote \(path) outside the host's folder")
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
            }
        }
    }

    func testAFolderWithNothingToDocumentIsRefused() async throws {
        let folder = try Fixture.folder()
        try Fixture.write(["notes.txt": "a list", "logo.png": "not code"], into: folder)
        do {
            _ = try await AnyAgentPackage(DocumentationAgent.self).perform(Data(#"{"make": "site"}"#.utf8), host: AgentHost(directory: folder.path))
            XCTFail("a site was written for a folder with no code")
        } catch {
            XCTAssertTrue("\(error)".contains("holds no source file to document"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Docs").path))
    }

    func testAMissingMakeIsAnInputError() async {
        do {
            _ = try await AnyAgentPackage(DocumentationAgent.self).perform(Data(#"{"sources": ["Sources"]}"#.utf8))
            XCTFail("a call with no make ran")
        } catch {
            XCTAssertTrue("\(error)".contains("make"), "\(error)")
        }
    }
}
