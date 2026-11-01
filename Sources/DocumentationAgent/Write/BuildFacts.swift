//  WHAT: How to build and test a project, read off its manifests: what it requires (deployment targets, Swift, Node),
//        the commands that build it (each Xcode scheme for its platform, the Swift packages, the package.json scripts,
//        another tool's usual commands), and the commands that test it. One reading for the README, Building.md and
//        the site, so the three never disagree.
//  PIN:  ONLY WHAT THE PROJECT DECLARES. A scheme is built for the platform its target's SDK names, a test runs where
//        it can run unattended (a macOS scheme, a package), and an iOS scheme's tests are built for the simulator and
//        run from Xcode, since a command line cannot know which simulators this Mac has.

import Foundation

struct BuildFacts: Sendable {
    struct Command: Sendable {
        let title: String
        let command: String
    }

    var requirements: [String] = []
    var build: [Command] = []
    var test: [Command] = []
    /// The local packages that build on their own, beside the project.
    var packages: [(name: String, folder: String, hasTests: Bool)] = []

    init(_ manifest: ProjectManifest) {
        for project in manifest.xcode {
            let os = project.deployment.keys.sorted().map { "\($0) \(project.deployment[$0]!) or later" }
            if !os.isEmpty { requirements.append(ProjectModel.list(os) + " (\(project.path))") }
            if let swift = project.swiftVersion { requirements.append("Swift \(swift) language mode (\(project.path))") }
            let remote = project.packages.filter { $0.url != nil }
            if !remote.isEmpty { requirements.append("Swift packages Xcode resolves on first open: " + ProjectModel.list(remote.map(\.name))) }
            let flag = manifest.workspace.map { "-workspace \(Self.quoted($0))" } ?? "-project \(Self.quoted(project.path))"
            build.append(Command(title: "Open it in Xcode", command: "open \(Self.quoted(manifest.workspace ?? project.path))"))
            for scheme in project.schemes {
                let destination = project.destination(scheme).map { " -destination '\($0)'" } ?? ""
                build.append(Command(title: "The \(scheme.name) scheme", command: "xcodebuild \(flag) -scheme \(Self.quoted(scheme.name))\(destination) build"))
                guard scheme.tests else { continue }
                if project.destination(scheme) == "platform=macOS" {
                    test.append(Command(title: "The \(scheme.name) scheme's tests", command: "xcodebuild \(flag) -scheme \(Self.quoted(scheme.name)) -destination 'platform=macOS' test"))
                } else {
                    test.append(Command(title: "The \(scheme.name) scheme's tests, built for the simulator; run them from Xcode with Product › Test",
                                        command: "xcodebuild \(flag) -scheme \(Self.quoted(scheme.name))\(destination) build-for-testing"))
                }
            }
        }
        if let package = manifest.package {
            if let tools = package.toolsVersion { requirements.append("Swift \(tools) or later (Package.swift's tools version)") }
            if !package.platforms.isEmpty { requirements.append(ProjectModel.list(package.platforms.map { $0 + " or later" }) + " (Package.swift)") }
            build.append(Command(title: "The package", command: "swift build"))
            for product in package.products where product.kind == "executable" {
                build.append(Command(title: "Run \(product.name)", command: "swift run \(product.name)"))
            }
            if package.targets.contains(where: \.isTest) { test.append(Command(title: "The package's tests", command: "swift test")) }
        }
        for package in manifest.localPackages {
            packages.append((package.name, package.folder, package.targets.contains(where: \.isTest)))
        }
        if let node = manifest.node {
            if let engine = node.engines["node"] { requirements.append("Node \(engine)") }
            build.append(Command(title: "Install its dependencies", command: "\(node.runner) install"))
            for (name, _) in node.scripts where name != "test" && !name.hasPrefix("pre") && !name.hasPrefix("post") {
                build.append(Command(title: "The `\(name)` script", command: node.command(name)))
            }
            if node.scripts.contains(where: { $0.name == "test" }) { test.append(Command(title: "Its tests", command: node.command("test"))) }
        }
        for tool in manifest.tools {
            switch tool {
            case "go.mod":
                build.append(Command(title: "The Go module", command: "go build ./..."))
                test.append(Command(title: "Its tests", command: "go test ./..."))
            case "Cargo.toml":
                build.append(Command(title: "The crate", command: "cargo build"))
                test.append(Command(title: "Its tests", command: "cargo test"))
            case "pyproject.toml": build.append(Command(title: "Install it", command: "pip install -e ."))
            case "requirements.txt": build.append(Command(title: "Install its dependencies", command: "pip install -r requirements.txt"))
            case "Makefile": build.append(Command(title: "Its Makefile", command: "make"))
            case "build.gradle", "build.gradle.kts":
                build.append(Command(title: "The Gradle build", command: "./gradlew build"))
                test.append(Command(title: "Its tests", command: "./gradlew test"))
            default: break
            }
        }
    }

    /// `name` quoted for a shell when it holds a space or a parenthesis.
    static func quoted(_ name: String) -> String {
        name.contains(where: { " ()'&;".contains($0) }) ? "\"\(name)\"" : name
    }

    /// The local packages' commands, one a package.
    var packageCommands: [Command] {
        packages.flatMap { p in
            [Command(title: "\(p.name), on its own", command: "swift build --package-path \(Self.quoted(p.folder))")]
                + (p.hasTests ? [Command(title: "\(p.name)'s tests", command: "swift test --package-path \(Self.quoted(p.folder))")] : [])
        }
    }
}
