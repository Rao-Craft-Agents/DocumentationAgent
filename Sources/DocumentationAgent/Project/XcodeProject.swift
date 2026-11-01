//  WHAT: An Xcode project, read off its `project.pbxproj` (an old-style property list Foundation parses) and its shared
//        schemes: each target with what it makes and the platform it builds for, the deployment targets, the Swift
//        version, the Swift packages it depends on, and each scheme with the target it builds and whether it tests.

import Foundation

struct XcodeProject: Sendable {
    struct Target: Sendable {
        let name: String
        let productType: String
        let sdk: String?
        let platforms: [String]
        var kind: String {
            switch productType {
            case let t where t.hasSuffix(".application"): return "app"
            case let t where t.hasSuffix(".app-extension") || t.contains("extensionkit"): return "app extension"
            case let t where t.contains("unit-test"): return "unit tests"
            case let t where t.contains("ui-testing"): return "UI tests"
            case let t where t.contains("framework"): return "framework"
            case let t where t.contains("library"): return "library"
            case let t where t.contains("tool"): return "command-line tool"
            case let t where t.contains("watchapp"): return "watch app"
            case let t where t.contains("widget"): return "widget"
            default: return productType.components(separatedBy: ".").last ?? productType
            }
        }
    }

    struct Scheme: Sendable {
        let name: String
        let target: String?
        let tests: Bool
    }

    struct PackageReference: Sendable {
        let name: String
        let url: String?
        let path: String?
        let requirement: String?
    }

    /// The `.xcodeproj` folder, from the project's root.
    let path: String
    let name: String
    let targets: [Target]
    let schemes: [Scheme]
    let packages: [PackageReference]
    let deployment: [String: String]
    let swiftVersion: String?

    init?(folder: URL, path: String) {
        let pbx = folder.appendingPathComponent("project.pbxproj")
        guard let data = try? Data(contentsOf: pbx),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objects = plist["objects"] as? [String: [String: Any]], let rootID = plist["rootObject"] as? String,
              let root = objects[rootID] else { return nil }
        self.path = path
        name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        func settings(_ listID: Any?) -> [[String: Any]] {
            guard let id = listID as? String, let list = objects[id], let configs = list["buildConfigurations"] as? [String] else { return [] }
            return configs.compactMap { objects[$0]?["buildSettings"] as? [String: Any] }
        }
        let projectSettings = settings(root["buildConfigurationList"])
        var deployment: [String: String] = [:]
        var swift: String?
        func note(_ all: [[String: Any]]) {
            for s in all {
                for (key, os) in [("IPHONEOS_DEPLOYMENT_TARGET", "iOS"), ("MACOSX_DEPLOYMENT_TARGET", "macOS"), ("TVOS_DEPLOYMENT_TARGET", "tvOS"),
                                  ("WATCHOS_DEPLOYMENT_TARGET", "watchOS"), ("XROS_DEPLOYMENT_TARGET", "visionOS")] {
                    if let value = s[key] as? String, deployment[os] == nil || value.compare(deployment[os]!, options: .numeric) == .orderedAscending {
                        deployment[os] = value
                    }
                }
                if swift == nil, let value = s["SWIFT_VERSION"] as? String { swift = value }
            }
        }
        note(projectSettings)
        var targets: [Target] = []
        for id in (root["targets"] as? [String]) ?? [] {
            guard let object = objects[id], (object["isa"] as? String) == "PBXNativeTarget", let targetName = object["name"] as? String else { continue }
            let own = settings(object["buildConfigurationList"])
            note(own)
            let sdk = (own.compactMap { $0["SDKROOT"] as? String }.first ?? projectSettings.compactMap { $0["SDKROOT"] as? String }.first)
            let supported = (own.compactMap { $0["SUPPORTED_PLATFORMS"] as? String }.first ?? "").split(separator: " ").map(String.init)
            targets.append(Target(name: targetName, productType: object["productType"] as? String ?? "", sdk: sdk, platforms: supported))
        }
        self.targets = targets
        self.deployment = deployment
        swiftVersion = swift
        var packages: [PackageReference] = []
        for id in (root["packageReferences"] as? [String]) ?? [] {
            guard let object = objects[id] else { continue }
            if let url = object["repositoryURL"] as? String {
                var named = (url as NSString).lastPathComponent
                if named.hasSuffix(".git") { named = String(named.dropLast(4)) }
                var requirement: String?
                if let r = object["requirement"] as? [String: Any], let kind = r["kind"] as? String {
                    switch kind {
                    case "revision": requirement = (r["revision"] as? String).map { "at \($0.prefix(7))" }
                    case "branch": requirement = (r["branch"] as? String).map { "branch \($0)" }
                    case "exactVersion": requirement = (r["version"] as? String).map { "exactly \($0)" }
                    case "upToNextMajorVersion", "upToNextMinorVersion": requirement = (r["minimumVersion"] as? String).map { "from \($0)" }
                    case "versionRange": requirement = [r["minimumVersion"], r["maximumVersion"]].compactMap { $0 as? String }.joined(separator: "..<").nonEmpty
                    default: requirement = kind
                    }
                }
                packages.append(PackageReference(name: named, url: url, path: nil, requirement: requirement))
            } else if let relative = object["relativePath"] as? String ?? object["path"] as? String {
                packages.append(PackageReference(name: (relative as NSString).lastPathComponent, url: nil, path: relative, requirement: nil))
            }
        }
        self.packages = packages.sorted { $0.name.lowercased() < $1.name.lowercased() }
        var schemes: [Scheme] = []
        let schemeFolder = folder.appendingPathComponent("xcshareddata/xcschemes")
        for file in ((try? FileManager.default.contentsOfDirectory(atPath: schemeFolder.path)) ?? []).sorted() where file.hasSuffix(".xcscheme") {
            let text = (try? String(contentsOf: schemeFolder.appendingPathComponent(file), encoding: .utf8)) ?? ""
            let blueprint = text.range(of: #"BlueprintName\s*=\s*"([^"]+)""#, options: .regularExpression).map { String(text[$0]).components(separatedBy: "\"")[1] }
            schemes.append(Scheme(name: String(file.dropLast(".xcscheme".count)), target: blueprint, tests: text.contains("<TestableReference")))
        }
        if schemes.isEmpty {
            // Xcode makes a scheme for every target it is opened with; the apps and tools are the ones to build.
            schemes = targets.filter { ["app", "command-line tool", "framework"].contains($0.kind) }.map { Scheme(name: $0.name, target: $0.name, tests: false) }
        }
        self.schemes = schemes
    }

    /// The `-destination` a scheme builds for: the simulator for an iOS target, this Mac for a macOS one.
    func destination(_ scheme: Scheme) -> String? {
        let target = targets.first { $0.name == scheme.target }
        let sdk = target?.sdk ?? ""
        if sdk.hasPrefix("iphone") { return "generic/platform=iOS Simulator" }
        if sdk.hasPrefix("macosx") { return "platform=macOS" }
        if sdk.hasPrefix("xros") { return "generic/platform=visionOS Simulator" }
        if sdk.hasPrefix("appletv") { return "generic/platform=tvOS Simulator" }
        if sdk.hasPrefix("watch") { return "generic/platform=watchOS Simulator" }
        let words = (scheme.name + " " + (scheme.target ?? "")).lowercased()
        if words.contains("ios") { return "generic/platform=iOS Simulator" }
        if words.contains("macos") || words.contains("mac") { return "platform=macOS" }
        return nil
    }
}
