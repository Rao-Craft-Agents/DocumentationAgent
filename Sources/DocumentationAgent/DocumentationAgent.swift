//  WHAT: The documentation of a codebase, written from its code, as a Granite agent package: a README, Markdown docs,
//        or an interactive static site with a code explorer. The package reads the project (its manifest, its folders,
//        every file), walks every Swift file with a lexer and a brace walk, matches its calls and its Granite flows, and
//        writes what the code says of itself; the host's model is asked only for prose, each claim citing a file.
//  IN:   Input: what to make, where, from which folders, the title, tagline, features and licence a README names, the
//        trails a site walks, whether it carries the ask orb, how many times a model's answer may be revised.
//  OUT:  DocumentationResult: the files written, the site's address, the counts, and what was left out and why.
//  PIN:  FACTS FROM THE CODE, PROSE FROM THE MODEL, NOTHING INVENTED. Every structure, list, tree, table and page is
//        read off the project the same way every time; the model writes a paragraph, a feature list, a folder's
//        overview, each bounded and grounded in a digest of the code, each claim naming a file that exists. With no
//        model those sections are left out and the answer says so; nothing is ever filled with placeholder text.
//  PIN:  NO KEY IS EVER WRITTEN. The site's ask orb reads a key only from `local/ask.js`, a file the person writes and
//        the site's own `.gitignore` keeps out of the repository.

import Foundation
import GraniteAgents

public struct DocumentationAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// What to write: `readme`, `markdown` or `site`.
        public var make: DocumentationMake
        /// Where the files go, relative to the project: its root for a README, `Docs` for Markdown, `Docs/site` for a site.
        public var into: String?
        /// The folders to read, relative to the project; the whole project when left out.
        public var sources: [String]?
        /// The project's name, as the README and the site title it; read off its manifest when left out.
        public var title: String?
        /// One line under the title.
        public var tagline: String?
        /// The README's feature lines, when the person gives them; the model writes them from the code otherwise.
        public var features: [String]?
        /// The licence the README names, written as `LICENSE` when the project has none.
        public var license: DocumentationLicense?
        /// Walks through the code for the site: `name: Type.member → Service.Reducer → …`.
        public var trails: [String]?
        /// Whether the site carries the ask orb.
        public var ask: Bool?
        /// How many times a model's answer may be asked again after it fails a check; 3 when left out.
        public var rounds: Int?
        /// The host's folder.
        public var directory: String?

        public init(make: DocumentationMake, into: String? = nil, sources: [String]? = nil, title: String? = nil, tagline: String? = nil,
                    features: [String]? = nil, license: DocumentationLicense? = nil, trails: [String]? = nil, ask: Bool? = nil,
                    rounds: Int? = nil, directory: String? = nil) {
            self.make = make; self.into = into; self.sources = sources; self.title = title; self.tagline = tagline
            self.features = features; self.license = license; self.trails = trails; self.ask = ask; self.rounds = rounds
            self.directory = directory
        }
    }

    public typealias Event = DocumentationFrame
    public typealias Output = DocumentationResult
    public typealias Compute = Void

    public static let word = "docs"
    public static let summary = "documents a codebase from its code: a README, Markdown docs, or an interactive static site with a code explorer, its call graph and its Granite flows."
    public static let fields = [
        "make": "readme writes README.md; markdown writes Docs/ (Architecture.md, a page per top-level folder, Glossary.md, Building.md); site writes Docs/site/, opened from file:// with no server",
        "into": "where the files go, relative to the project; the project's root for readme, Docs for markdown, Docs/site for site",
        "sources": "the folders to read, relative to the project; the whole project when left out",
        "title": "the project's name; read off its manifest or Xcode project when left out",
        "tagline": "one line under the title, in the person's words",
        "features": "the README's feature lines when the person gave them; otherwise the model writes them from the code, each citing a file",
        "license": "the licence the README names; written as LICENSE when the project has none",
        "trails": "walks the site's Explorer follows, one a line: `name: Type.member → Service.Reducer → Other.member`; derived from the Granite flows when left out",
        "ask": "true adds the ask orb: a chat about the code that answers with a key the person puts in Docs/site/local/ask.js",
        "rounds": "how many times the model's prose may be asked again after it fails a check; 3 when left out",
    ]
    public static let guide = """
        Tag docs to document the project you are in, from its code. Call it before reading the code: it reads the \
        project itself and names every file it wrote. One call per kind of documentation, `make`:
        - `readme` writes README.md: what the project is and its features (the model's prose, each claim citing a \
        file), the requirements, how to build and test it (read off its Xcode schemes, SwiftPM products and \
        package.json scripts), its folder tree with a line each, and how it is built (services, components, \
        packages). Example: `{"make": "readme", "title": "Larder", "tagline": "A pantry and recipe planner for iOS \
        and macOS.", "license": "MIT"}`.
        - `markdown` writes Docs/: Architecture.md (its modules in dependency order, targets, folders, services), one \
        page per top-level folder led by what its code says of itself (headers, doc comments, declarations, Granite \
        services with their events and relays, components with what they read), Glossary.md (its types) and \
        Building.md. Example: `{"make": "markdown", "sources": ["Services", "Components", "Shared"]}`.
        - `site` writes Docs/site/, an interactive site that opens from file:// with no server: a page per folder, \
        every file with its declarations and line anchors, an Explorer with the call graph (exact, likely, ambiguous) \
        and the Granite flows ranked by relays, trails, search, and every Markdown file. Example: `{"make": "site", \
        "trails": ["save a recipe: RecipeEditor.save → RecipeService.Save → PantryService.Reserve"], "ask": true}`.
        `sources` names the folders to read (the whole project when left out); `into` moves the output. `trails` are \
        lines `name: Step → Step → …`, each step a declaration as the code names it (`Type.method`, `App.init`, a \
        reducer `Service.Reducer`); left out, the site derives them from the Granite flows: boot, then each \
        service's events. `features` are the person's own lines; give them only when the person said them. `ask` \
        true adds a chat orb whose key the person writes into Docs/site/local/ask.js; no key is ever written. A step \
        that names nothing in the code or a folder that does not exist is refused with the reason, and nothing is \
        written. Without a model the prose is left out and the answer says so. Not for one type's API reference or \
        for comments in the code.
        """

    public static func output(from events: [DocumentationFrame]) -> DocumentationResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<DocumentationFrame, Error> {
        // The folder is the call's, else the host's, then the process's: a host on the wire may give it only in its
        // AgentHost, and a run that fell back to the working folder would write wherever its runner was started.
        var input = input
        if input.directory == nil { input.directory = context.host.directory }
        let call = input
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await DocumentationRun(input: call, host: context.host, yield: { continuation.yield($0) }).run()
                    continuation.yield(.written(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
