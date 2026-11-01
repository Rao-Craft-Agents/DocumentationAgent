//  WHAT: A project's README, from its code: the title and tagline, the opening and the features (the model's prose,
//        each sentence linking the files that show it, or the person's own feature lines), the requirements and how to
//        build and test it (read off its schemes, products and scripts), its folder tree with a line each, how it is
//        built (services, components, packages, targets), and its licence.
//  PIN:  A SECTION WITH NOTHING TRUE TO SAY IS LEFT OUT. With no model the opening and the features are left out and
//        the call's notes say so; a project with no tests says that in a sentence rather than inventing a command.

import Foundation

struct ReadmeWriter {
    let model: ProjectModel
    let build: BuildFacts
    /// The folder the README is written in, from the project's root.
    let folder: String
    var tagline: String?
    var features: [String]?
    var opening: ProseAnswer?
    /// What the code says the project is (its package's comment, its entry's doc), cited: the opening when the model
    /// wrote none.
    var about: (text: String, source: String)?
    var license: (name: String, file: String)?

    func text() -> String {
        var out: [String] = ["# \(model.title)", ""]
        if let tagline, !tagline.isEmpty { out += [Markdown.inline(tagline), ""] }
        if let opening, !opening.sentences.isEmpty {
            out.append(opening.sentences.map { sentence($0.text, $0.files) }.joined(separator: " "))
            out.append("")
        } else if let about {
            out += [Markdown.inline(about.text) + " *(From [\((about.source as NSString).lastPathComponent)](\(Markdown.link(about.source, from: folder))).)*", ""]
        }
        let personal = (features ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let written = opening?.features ?? []
        if !personal.isEmpty || !written.isEmpty {
            out += ["## Features", ""]
            if !personal.isEmpty {
                out += personal.map { "- " + Markdown.inline($0) }
            } else {
                out += written.map { "- **\(Markdown.inline($0.title.trimmingCharacters(in: .whitespaces)))**: " + sentence($0.text, $0.files) }
            }
            out.append("")
        }
        out += requirements()
        out += building()
        out += testing()
        out += structure()
        out += howItIsBuilt()
        if let license {
            out += ["## License", "", "\(license.name): see [\(license.file)](\(Markdown.link(license.file, from: folder))).", ""]
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    /// A sentence of the model's, with the files it cites linked after it.
    func sentence(_ text: String, _ files: [String]) -> String {
        let trimmed = Markdown.inline(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !files.isEmpty else { return trimmed }
        let links = files.map { "[\(($0 as NSString).lastPathComponent)](\(Markdown.link($0, from: folder)))" }.joined(separator: ", ")
        let body = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        return body + " (" + links + ")."
    }

    private func requirements() -> [String] {
        guard !build.requirements.isEmpty else { return [] }
        return ["## Requirements", ""] + build.requirements.map { "- " + $0 } + [""]
    }

    private func building() -> [String] {
        var out: [String] = []
        if !build.build.isEmpty {
            out += ["## Building", "", "```sh"]
            for command in build.build { out += ["# " + command.title, command.command] }
            out += ["```", ""]
        }
        if !build.packages.isEmpty {
            let names = build.packages.map { "[\($0.name)](\(Markdown.link($0.folder, from: folder)))" }
            out += ["The project's own Swift packages build on their own too, each with `swift build --package-path <its folder>`: "
                    + ProjectModel.list(names) + ".", ""]
        }
        return out
    }

    private func testing() -> [String] {
        var out = ["## Testing", ""]
        let tested = build.packages.filter(\.hasTests)
        if build.test.isEmpty && tested.isEmpty {
            out += ["The project declares no tests: no scheme runs any, and no package has a test target.", ""]
            return out
        }
        if !build.test.isEmpty {
            out.append("```sh")
            for command in build.test { out += ["# " + command.title, command.command] }
            out += ["```", ""]
        }
        if !tested.isEmpty {
            out += ["Its packages' tests run with `swift test --package-path <its folder>`: " + ProjectModel.list(tested.map(\.name)) + ".", ""]
        }
        return out
    }

    private func structure() -> [String] {
        let tree = FolderTree(model: model).lines()
        guard tree.count > 1 else { return [] }
        return ["## Structure", "", "```"] + tree + ["```", ""]
    }

    private func howItIsBuilt() -> [String] {
        var out: [String] = []
        if !model.services.isEmpty {
            out += ["### Services", "",
                    "Each service is a Granite service: its center holds the state, a reducer answers each event, and its rank is one above the highest service it reaches.", "",
                    "| Service | Rank | Events | Reaches |", "|---|---|---|---|"]
            for s in model.services {
                out.append("| [\(s.name)](\(Markdown.link(s.path, from: folder))) | \(s.rank) | " + Markdown.cell(s.events.map { "`\($0.event)`" }.joined(separator: ", ").nonEmpty ?? "none")
                           + " | " + Markdown.cell(s.reaches.joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        if !model.components.isEmpty {
            out += ["### Components", "", "| Component | Reads | Events |", "|---|---|---|"]
            for c in model.components {
                out.append("| [\(c.name)](\(Markdown.link(c.path, from: folder))) | " + Markdown.cell(c.relays.joined(separator: ", ").nonEmpty ?? "–") + " | "
                           + Markdown.cell(c.events.map { "`\($0.event)`" }.joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        let packages = model.manifest.localPackages
        if !packages.isEmpty {
            out += ["### Packages", "", "| Package | Folder | Products |", "|---|---|---|"]
            for p in packages {
                out.append("| \(p.name) | [\(p.folder)](\(Markdown.link(p.folder, from: folder))) | " + Markdown.cell(p.products.map(\.name).joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        if let p = model.manifest.package, !p.targets.isEmpty {
            out += ["### Targets", "", "| Target | Kind | Depends on |", "|---|---|---|"]
            for t in p.targets {
                let deps = t.targets + t.products.map(\.name)
                out.append("| [\(t.name)](\(Markdown.link(p.sourceFolder(t), from: folder))) | \(t.kind) | " + Markdown.cell(deps.joined(separator: ", ").nonEmpty ?? "–") + " |")
            }
            out.append("")
        }
        for x in model.manifest.xcode where !x.targets.isEmpty {
            out += ["### \(x.path)", "", "| Target | What it makes | Builds for |", "|---|---|---|"]
            out += x.targets.map { "| \(Markdown.cell($0.name)) | \($0.kind) | \($0.sdk ?? "–") |" }
            out.append("")
        }
        let external = model.manifest.xcode.flatMap(\.packages).filter { $0.url != nil } + []
        let fromPackage = (model.manifest.package?.dependencies ?? []).filter { $0.url != nil }
        if !external.isEmpty || !fromPackage.isEmpty {
            let names = external.map { "[\($0.name)](\($0.url!))" + ($0.requirement.map { " (\($0))" } ?? "") }
                + fromPackage.map { "[\($0.name)](\($0.url!))" + ($0.requirement.map { " (\($0))" } ?? "") }
            out += ["It depends on " + ProjectModel.list(names) + ".", ""]
        }
        return out.isEmpty ? [] : ["## How it is built", ""] + out
    }
}
