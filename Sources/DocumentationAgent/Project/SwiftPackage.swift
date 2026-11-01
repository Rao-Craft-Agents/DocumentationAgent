//  WHAT: A `Package.swift`, read as text: the package's name, its tools version, the platforms it needs, its products,
//        the packages it depends on, its targets with what each depends on, and the layers those dependencies make.
//  PIN:  READ, NOT RUN. `swift package dump-package` would build and run the manifest; a documentation call must stay
//        quick and change nothing, so the manifest's common shapes are read off its text, and an unusual one is
//        documented as far as its text goes.

import Foundation

struct SwiftPackage: Sendable {
    struct Product: Sendable { let kind: String; let name: String; let targets: [String] }
    struct Dependency: Sendable { let name: String; let url: String?; let path: String?; let requirement: String?; let line: Int }
    struct Target: Sendable {
        let kind: String
        let name: String
        let line: Int
        let path: String?
        let targets: [String]
        let products: [(name: String, package: String)]
        var layer = 0
        var isTest: Bool { kind == "testTarget" }
    }

    /// The folder it is in, from the project's root: `.` for the project's own.
    let folder: String
    let name: String
    let toolsVersion: String?
    let platforms: [String]
    let products: [Product]
    let dependencies: [Dependency]
    private(set) var targets: [Target]
    /// Target names by layer: a target's layer is the longest chain of the package's own targets under it.
    private(set) var layers: [[String]] = []
    /// The comment the manifest opens with, past its tools version.
    let about: String?

    private static let nameLine = Pattern(#"Package\s*\(\s*name:\s*"([^"]+)""#)
    private static let product = Pattern(#"\.(executable|library|plugin)\s*\(\s*name:\s*"([^"]+)"[^)]*?targets:\s*\[([^\]]*)\]"#)
    private static let package = Pattern(#"\.package\s*\((?:\s*name:\s*"[^"]*"\s*,)?\s*(?:url:\s*"([^"]+)"|path:\s*"([^"]+)")(?:\s*,\s*(?:(branch|from|exact|revision)\s*:\s*"([^"]+)"|(\.upToNextMajor|\.upToNextMinor|\.exact)\s*\(\s*from:\s*"([^"]+)"\s*\)|"([^"]+)"\s*\.\.[.<]\s*"([^"]+)"))?"#)
    private static let targetStart = Pattern(#"\.(target|executableTarget|testTarget|macro|plugin|binaryTarget|systemLibrary)\s*\("#)
    private static let quoted = Pattern(#""([^"]+)""#)
    private static let productDependency = Pattern(#"\.product\s*\(\s*name:\s*"([^"]+)"\s*,\s*package:\s*"([^"]+)"\s*\)"#)
    private static let platform = Pattern(#"\.(macOS|iOS|tvOS|watchOS|visionOS|macCatalyst|linux)\s*\(\s*(?:\.v(\d+(?:_\d+)?)|"([^"]+)")"#)

    init?(text: String, folder: String) {
        guard let nameMatch = Self.nameLine.first(text), let name = nameMatch.group(1, in: text) else { return nil }
        self.folder = folder
        self.name = name
        let lines = text.components(separatedBy: "\n")
        if let first = lines.first, let found = first.range(of: #"swift-tools-version:\s*[\d.]+"#, options: .regularExpression) {
            toolsVersion = first[found].split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            toolsVersion = nil
        }
        // SwiftPM's own template line says nothing of the package.
        let comment = lines.dropFirst().prefix { $0.hasPrefix("//") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("swift-tools-version") }
        about = comment.isEmpty ? nil : comment.joined(separator: " ")
        platforms = Self.platform.matches(text).compactMap { m in
            guard let os = m.group(1, in: text) else { return nil }
            let version = m.group(2, in: text).map { $0.replacingOccurrences(of: "_", with: ".") } ?? m.group(3, in: text) ?? ""
            return "\(os == "macOS" ? "macOS" : os) \(version)"
        }
        products = Self.product.matches(text).compactMap { m in
            guard let kind = m.group(1, in: text), let name = m.group(2, in: text), let list = m.group(3, in: text) else { return nil }
            return Product(kind: kind, name: name, targets: Self.quoted.matches(list).compactMap { $0.group(1, in: list) })
        }
        dependencies = Self.package.matches(text).map { m in
            let url = m.group(1, in: text), path = m.group(2, in: text)
            var requirement: String?
            if let kind = m.group(3, in: text), let value = m.group(4, in: text) { requirement = "\(kind) \(value)" }
            else if let kind = m.group(5, in: text), let value = m.group(6, in: text) { requirement = "\(kind.dropFirst()) \(value)" }
            else if let low = m.group(7, in: text), let high = m.group(8, in: text) { requirement = "\(low)..<\(high)" }
            var named = ((url ?? path ?? "") as NSString).lastPathComponent
            if named.hasSuffix(".git") { named = String(named.dropLast(4)) }
            let line = text.utf16.prefix(m.range.location).filter { $0 == 10 }.count + 1
            return Dependency(name: named, url: url, path: path, requirement: requirement, line: line)
        }
        let ns = text as NSString
        let starts = Self.targetStart.matches(text)
        var targets: [Target] = []
        for (i, m) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: m.range.location, length: end - m.range.location))
            guard let kind = m.group(1, in: text), let targetName = block.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression)
                .map({ String(block[$0]).components(separatedBy: "\"")[1] }) else { continue }
            var dependencies = ""
            if let open = block.range(of: #"dependencies:\s*\["#, options: .regularExpression) {
                var depth = 1
                var k = open.upperBound
                while k < block.endIndex, depth > 0 {
                    if block[k] == "[" { depth += 1 } else if block[k] == "]" { depth -= 1 }
                    if depth > 0 { k = block.index(after: k) }
                }
                dependencies = String(block[open.upperBound..<k]).replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
            }
            let productDeps = Self.productDependency.matches(dependencies).compactMap { d -> (String, String)? in
                guard let n = d.group(1, in: dependencies), let p = d.group(2, in: dependencies) else { return nil }
                return (n, p)
            }
            let stripped = dependencies.replacingOccurrences(of: #"\.product\s*\([^)]*\)"#, with: "", options: .regularExpression)
            let named = Self.quoted.matches(stripped).compactMap { $0.group(1, in: stripped) }
            let path = block.range(of: #"path:\s*"([^"]+)""#, options: .regularExpression).map { String(block[$0]).components(separatedBy: "\"")[1] }
            let line = text.utf16.prefix(m.range.location).filter { $0 == 10 }.count + 1
            targets.append(Target(kind: kind, name: targetName, line: line, path: path, targets: named, products: productDeps))
        }
        self.targets = targets
        layers = []
        computeLayers()
    }

    private mutating func computeLayers() {
        let byName = Dictionary(targets.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var depth: [String: Int] = [:]
        func depthOf(_ name: String, _ trail: Set<String>) -> Int {
            if let known = depth[name] { return known }
            if trail.contains(name) { return 0 }
            let inner = (byName[name]?.targets ?? []).filter { byName[$0] != nil }
            let value = inner.isEmpty ? 0 : 1 + (inner.map { depthOf($0, trail.union([name])) }.max() ?? 0)
            depth[name] = value
            return value
        }
        var layered: [Int: [String]] = [:]
        for i in targets.indices where !targets[i].isTest {
            targets[i].layer = depthOf(targets[i].name, [])
            layered[targets[i].layer, default: []].append(targets[i].name)
        }
        layers = layered.keys.sorted().map { layered[$0]!.sorted() }
    }

    /// Where a target's sources are: its `path`, else `Sources/<name>` (or `Tests/<name>` for a test target).
    func sourceFolder(_ target: Target) -> String {
        let base = folder == "." ? "" : folder + "/"
        return base + (target.path ?? ((target.isTest ? "Tests/" : "Sources/") + target.name))
    }

    var swiftVersion: String? { toolsVersion }
}
