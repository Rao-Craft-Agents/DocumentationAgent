import Foundation
import XCTest
@testable import DocumentationAgent

/// The lexer and the brace walk, held to the shapes that break a naive one: a brace inside text is never counted, and
/// every declaration is found where a plain count of its keyword says it is.
final class SwiftSourceTests: XCTestCase {
    private func walk(_ text: String) -> SwiftSource { SwiftSource(text: text, path: "Sources/App/File.swift", module: "App") }
    private func names(_ source: SwiftSource) -> [String] { source.scopes.indices.map { source.qualified($0) } }

    func testBracesInsideTextAreNeverCounted() {
        let source = walk(##"""
        struct Menu {
            let open = "{ not a scope"
            let raw = #"a "quoted" \(not interpolated) {"#
            let hashed = #"value: \#(count) }"#
            let block = """
                { "a brace in a block" }
                """
            let pattern = #/\{[a-z]+\}/#
            /* a comment { /* nested } */ still a comment { */
            func title(for count: Int) -> String {
                "\(count > 1 ? "{many}" : "}one{") items"
            }
        }
        """##)
        XCTAssertNil(source.problem)
        XCTAssertTrue(source.balanced)
        XCTAssertEqual(names(source), ["Menu", "Menu.title"])
        XCTAssertEqual(source.scopes[1].labels, ["for"])
        XCTAssertEqual(source.scopes[0].end, 13)
        let (walked, counted) = source.keywordCounts()
        XCTAssertEqual(walked, counted)
    }

    func testDeclarationsTheirLinesDocsAndIds() {
        let source = walk("""
        //  WHAT: The pantry's shelf: what is on it and how much.
        //        A second line of the header.
        //  PIN:  One writer.

        import Foundation

        /// A shelf of items.
        /// It keeps them in order.
        @MainActor
        public final class Shelf: Store {
            /// Adds an item.
            func add(_ item: Item, count: Int = 1) {}
            func add(_ item: Item, count: Int = 1) {}
            init?(name: String) {}
            subscript(index: Int) -> Item { items[index] }
            var total: Int { items.count }
            static func == <T: Equatable>(a: T, b: T) -> Bool { true }
            static prefix func - (shelf: Shelf) -> Shelf { shelf }
            enum Sort: String { case name, count = "n" ; case `default` }
            deinit {}
        }

        extension Shelf.Sort {
            var label: String { rawValue }
        }
        """)
        XCTAssertNil(source.problem)
        XCTAssertEqual(source.header?.what, 1...2)
        XCTAssertEqual(source.header?.pin, 3...3)
        XCTAssertEqual(source.what, "The pantry's shelf: what is on it and how much. A second line of the header.")
        XCTAssertEqual(source.summary, "The pantry's shelf: what is on it and how much.")
        let shelf = source.scopes[0]
        XCTAssertEqual(shelf.kind, "C")
        XCTAssertEqual(shelf.decl, 9, "the attribute line belongs to the declaration")
        XCTAssertEqual(shelf.sig, 10)
        XCTAssertEqual(shelf.doc, 7...8)
        XCTAssertEqual(shelf.mods, "public final")
        XCTAssertEqual(source.scopes.map(\.kind), ["C", "f", "f", "i", "s", "v", "f", "f", "E", "d", "X", "v"])
        XCTAssertEqual(source.scopes[1].params.map(\.label), ["_", "count"])
        XCTAssertTrue(source.scopes[1].params[1].hasDefault)
        XCTAssertEqual(source.scopes[6].name, "==", "an operator ends where its generic clause begins")
        XCTAssertEqual(source.scopes[7].name, "-")
        XCTAssertEqual(source.scopes[8].cases, ["name", "count", "default"])
        XCTAssertEqual(source.ids(), [
            "Sources/App/File.swift:Shelf", "Sources/App/File.swift:Shelf.add(_:count:)", "Sources/App/File.swift:Shelf.add(_:count:)~2",
            "Sources/App/File.swift:Shelf.init(name:)", "Sources/App/File.swift:Shelf.subscript(index:)", "Sources/App/File.swift:Shelf.total",
            "Sources/App/File.swift:Shelf.==(a:b:)", "Sources/App/File.swift:Shelf.-(shelf:)", "Sources/App/File.swift:Shelf.Sort",
            "Sources/App/File.swift:Shelf.deinit", "Sources/App/File.swift:extension:Shelf.Sort", "Sources/App/File.swift:Shelf.Sort.label",
        ])
        let (walked, counted) = source.keywordCounts()
        XCTAssertEqual(walked, counted)
    }

    func testAProtocolsRequirementsHaveNoBraceAndAreFound() {
        let source = walk("""
        protocol Store {
            associatedtype Item
            var items: [Item] { get }
            func add(_ item: Item,
                     count: Int) -> Bool
            init(name: String)
            subscript(index: Int) -> Item { get }
        }
        """)
        XCTAssertEqual(names(source), ["Store", "Store.items", "Store.add", "Store.init", "Store.subscript"], "found once, by the walk or the scan")
        XCTAssertTrue(source.scopes.dropFirst().allSatisfy(\.isRequirement))
        XCTAssertEqual(source.scopes[2].labels, ["_", "count"])
        XCTAssertEqual(source.scopes[2].end, 5, "a requirement spans the lines of its parameters")
    }

    func testAClosureIsABlockAndNotADeclaration() {
        let source = walk("""
        func load() {
            var count: Int
            items.forEach { item in
                count += 1
            }
            let sorted = items.sorted { $0 < $1 }
            var observed = 0 {
                didSet { print(observed) }
            }
        }
        """)
        XCTAssertEqual(names(source), ["load"])
        XCTAssertEqual(source.scopes[0].end, 10)
    }

    func testAnIfBranchThatOpensABraceTwiceStillWalks() {
        let source = walk("""
        #if os(iOS)
        extension Picker: UIViewRepresentable {
        #else
        extension Picker: NSViewRepresentable {
        #endif
            func makeView() -> View { View() }
        }
        """)
        XCTAssertNil(source.problem)
        XCTAssertFalse(source.balanced, "one brace never closes, and the file says so")
        XCTAssertEqual(source.scopes.map(\.kind), ["X", "X", "f"], "every declaration is still found")
    }

    func testAFileTheLexerCannotFinishDeclaresNothing() {
        let source = walk("struct Broken {\n    let text = \"never closed\n}\n")
        XCTAssertNotNil(source.problem)
        XCTAssertTrue(source.scopes.isEmpty)
        XCTAssertEqual(source.lineCount, 3)
    }

    func testAnEditorsTemplateHeaderSaysNothing() {
        let source = walk("//\n//  Feed.swift\n//  App\n//\n//  Created by Someone on 7/1/22.\n//  Copyright (c) 2022 Someone. All rights reserved.\n//\n\nstruct Feed {}\n")
        XCTAssertNil(source.leadingProse)
        XCTAssertEqual(source.summary, "", "a template is not what the file is")
    }

    func testTheRecordIsWhatThePageReads() {
        let source = walk("/// A cup.\nstruct Cup {\n    func fill(to level: Int) {}\n}\n")
        guard case .object(let pairs) = source.record(first: 7) else { return XCTFail("not an object") }
        let record = Dictionary(uniqueKeysWithValues: pairs)
        XCTAssertEqual(record["first"], .int(7))
        XCTAssertEqual(record["lines"], .int(4))
        XCTAssertEqual(record["summary"], .string("A cup."))
        XCTAssertEqual(record["scopes"]?.text, #"[["S","Cup",null,"",2,2,[2,11],4,[1,1],-1,0],["f","fill",["to"],"",3,3,[3,29],3,null,0,8]]"#)
    }

    func testUTF16ColumnsMatchJavaScript() {
        let source = walk("let 🍳 = 1\nstruct Café { func ü() {} }\n")
        XCTAssertEqual(source.scopes.first?.braceColumn, 12, "the brace's column counts UTF-16 units, as String.slice does")
    }
}
