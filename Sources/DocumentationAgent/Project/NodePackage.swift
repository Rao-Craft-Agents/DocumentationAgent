//  WHAT: A `package.json`: the package's name and description, its scripts, and the Node it asks for.

import Foundation

struct NodePackage: Sendable {
    let folder: String
    let name: String?
    let description: String?
    /// The scripts in the order the file lists them.
    let scripts: [(name: String, command: String)]
    let engines: [String: String]
    let usesYarn: Bool
    let usesPnpm: Bool

    init?(text: String, folder: String, siblings: [String]) {
        guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.folder = folder
        name = json["name"] as? String
        description = json["description"] as? String
        let scriptMap = json["scripts"] as? [String: String] ?? [:]
        // The file's own order: JSONSerialization forgets it, so the keys are found in the text.
        let ordered = scriptMap.keys.sorted { a, b in
            (text.range(of: "\"\(a)\"")?.lowerBound ?? text.endIndex) < (text.range(of: "\"\(b)\"")?.lowerBound ?? text.endIndex)
        }
        scripts = ordered.map { ($0, scriptMap[$0]!) }
        engines = json["engines"] as? [String: String] ?? [:]
        usesYarn = siblings.contains("yarn.lock")
        usesPnpm = siblings.contains("pnpm-lock.yaml")
    }

    var runner: String { usesPnpm ? "pnpm" : usesYarn ? "yarn" : "npm" }

    func command(_ script: String) -> String {
        if script == "test" || script == "start" { return "\(runner) \(script)" }
        return runner == "npm" ? "npm run \(script)" : "\(runner) \(script)"
    }
}
