//  WHAT: One folder of the project as the documentation reads it: its kind (the root, a package, a package's target, a
//        group of a root's parts, a folder), its folders and files, its counts, and what it is from the code: its root
//        type `<Folder>.swift` by its WHAT or its doc comment, a target's type, the service or component it holds, the
//        package's comment, or the README it carries, each saying where it was read.

import Foundation

struct FolderFacts: Sendable {
    /// What the folder is, and where that is said.
    struct About: Sendable {
        let text: String
        /// what (a file's WHAT), doc (a type's doc comment), package (Package.swift's comment), readme, granite, group.
        let from: String
        let source: String?
        let line: Int?
        let type: String?
    }

    struct RootType: Sendable {
        let name: String
        let path: String
        let line: Int
        let kind: String
    }

    /// The folders that group a root's parts, named by the root they belong to.
    static let groups: Set<String> = ["Reducers", "Models", "Views", "Steps", "Values", "Support", "Ops", "Actions", "Listeners", "Styles",
                                      "Extensions", "Helpers", "Utilities", "Components", "Services"]

    let path: String
    let name: String
    let parent: String?
    var kind = "folder"
    var folders: [String] = []
    var files: [String] = []
    var files1 = 0, lines1 = 0, filesAll = 0, linesAll = 0, foldersAll = 0
    var about: About?
    /// What the folder holds, said from its code when nothing says what it is: its services, components, packages,
    /// targets, or the types its files declare.
    var holds: String?
    var rootType: RootType?
    /// The services and components declared in it or below.
    var services: [String] = []
    var components: [String] = []
    var package: String?

    var depth: Int { path == "." ? 0 : path.split(separator: "/").count }
}
