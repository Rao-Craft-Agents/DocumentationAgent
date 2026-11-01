//  WHAT: The project's modules in dependency order, read off its manifests and every Swift file's imports: each package
//        target is a module, the files no package holds are the app's, and a module sits one layer above the highest
//        module of the project it imports.

import Foundation

struct ModuleOrder {
    struct Module {
        let name: String
        /// Where it lives: a package target's folder, or the project's root for the app.
        let folder: String
        let kind: String
        var imports: Set<String> = []
        var layer = 0
        var files = 0
    }

    private(set) var modules: [Module] = []
    private static let importLine = Pattern(#"^\s*(?:@[\w]+(?:\([^)]*\))?\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)"#, options: [.anchorsMatchLines])

    init(_ model: ProjectModel) {
        var byName: [String: Module] = [:]
        var folders: [(prefix: String, name: String)] = []
        for package in model.manifest.packages {
            for target in package.targets where !target.isTest {
                let folder = package.sourceFolder(target)
                // Two packages may declare a target of one name; the first read keeps it.
                if byName[target.name] == nil {
                    byName[target.name] = Module(name: target.name, folder: folder, kind: package.folder == "." ? "target" : "target of \(package.name)")
                }
                folders.append((folder.hasSuffix("/") ? folder : folder + "/", target.name))
            }
        }
        let app = model.manifest.xcode.first?.name ?? model.title
        folders.sort { $0.prefix.count > $1.prefix.count }
        for file in model.swift {
            let owner = folders.first { file.path.hasPrefix($0.prefix) }?.name
            let isTest = owner == nil && file.path.split(separator: "/").contains { $0.lowercased().contains("test") }
            if isTest { continue }
            let name = owner ?? app
            if byName[name] == nil {
                byName[name] = Module(name: name, folder: ".", kind: model.manifest.xcode.isEmpty ? "the files no package holds" : "the app, \(model.manifest.xcode[0].path)")
            }
            byName[name]!.files += 1
            for m in Self.importLine.matches(file.text) {
                if let imported = m.group(1, in: file.text), imported != name { byName[name]!.imports.insert(imported) }
            }
        }
        let known = Set(byName.keys)
        for key in byName.keys { byName[key]!.imports = byName[key]!.imports.intersection(known) }
        var layer: [String: Int] = [:]
        func depth(_ name: String, _ trail: Set<String>) -> Int {
            if let known = layer[name] { return known }
            if trail.contains(name) { return 0 }
            let inner = byName[name]!.imports.map { depth($0, trail.union([name])) + 1 }.max() ?? 0
            layer[name] = inner
            return inner
        }
        for key in byName.keys { byName[key]!.layer = depth(key, []) }
        modules = byName.values.filter { $0.files > 0 }.sorted { ($0.layer, $0.name) < ($1.layer, $1.name) }
    }
}
