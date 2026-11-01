//  WHAT: How a project is built, read off its manifests: its own `Package.swift`, the local packages beside it, the Xcode
//        projects at its root, a `package.json`, and the other tools' files (`go.mod`, `Cargo.toml`, `pyproject.toml`),
//        and the name it goes by.

import Foundation

struct ProjectManifest: Sendable {
    let package: SwiftPackage?
    /// Every other `Package.swift` read, by folder: a project's local packages.
    let localPackages: [SwiftPackage]
    let xcode: [XcodeProject]
    /// A workspace at the root, which builds the projects and packages together.
    let workspace: String?
    let node: NodePackage?
    /// Other build tools the root names: the file that says so.
    let tools: [String]

    init(root: URL, packageFiles: [String]) {
        let manager = FileManager.default
        func read(_ rel: String) -> String? { try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8) }
        package = read("Package.swift").flatMap { SwiftPackage(text: $0, folder: ".") }
        localPackages = packageFiles.filter { $0 != "Package.swift" }.sorted().compactMap { rel in
            read(rel).flatMap { SwiftPackage(text: $0, folder: (rel as NSString).deletingLastPathComponent) }
        }
        let entries = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        xcode = entries.filter { $0.hasSuffix(".xcodeproj") }.compactMap { XcodeProject(folder: root.appendingPathComponent($0), path: $0) }
        workspace = entries.first { $0.hasSuffix(".xcworkspace") }
        node = read("package.json").flatMap { NodePackage(text: $0, folder: ".", siblings: entries) }
        tools = ["go.mod", "Cargo.toml", "pyproject.toml", "requirements.txt", "setup.py", "Makefile", "Gemfile", "build.gradle", "build.gradle.kts"]
            .filter { entries.contains($0) }
    }

    /// The project's name: the root package's, else its Xcode project's, else its `package.json`'s, else its folder's.
    func name(folder: String) -> String {
        package?.name ?? xcode.first?.name ?? node?.name ?? folder
    }

    /// Every Swift package the project holds, its own first.
    var packages: [SwiftPackage] { (package.map { [$0] } ?? []) + localPackages }
}
