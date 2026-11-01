//  WHAT: What the model is told when it writes prose: the rules a grounded paragraph follows, a worked answer for a
//        project of another domain (a recipe app) to copy the shape of and never the words, the keys as JSON Schema,
//        and, on a retry, what its last answer was refused for.
//  PIN:  THE EXAMPLE IS ANOTHER PROJECT'S. A local model copies the example it is shown; one drawn from the project it
//        writes about would come back as the example. `ProseCheck` refuses an answer that repeats the example's words.

import Foundation

enum ProsePrompt {
    static let rules = """
    You write a few sentences of documentation for a software project, from a digest of its code. Answer with one JSON object.
    - Say only what the digest shows: what the project is and does for the person who uses it, in plain words, present tense.
    - Every sentence names in `files` one to three files from the digest that show what it says, each path exactly as the digest writes it. A sentence no file in the digest shows is not written.
    - Never a number, a version, a platform, a library or a feature the digest does not state. No marketing words (powerful, seamless, robust, blazing, effortless, cutting-edge, simply). No Markdown, no links, no lists, no code blocks; backticks only around a name the code uses.
    - Each sentence is one sentence, at most 220 characters, ending with a period.
    """

    static let readmeRules = rules + """

    - `sentences`: two to four sentences that open the README: what the project is, then what it does and how it is put together, read off the folders, services and files.
    - `features`: three to seven things the project does for its user, each a `title` of two to five words, one sentence of `text`, and its `files`.
    """

    static let readmeOnlyOpening = rules + """

    - `sentences`: two to four sentences that open the README: what the project is, then what it does and how it is put together, read off the folders, services and files.
    """

    static let folderRules = rules + """

    - `sentences`: two or three sentences that say what this folder holds and how its parts work together, read off its files, its services and its components.
    """

    /// A README's opening for another project: what the model copies the shape of.
    static let readmeExample = #"""
    {"sentences": [
      {"text": "Larder is a pantry and meal planner for iPhone and Mac that keeps what is on the shelf beside the recipes that use it.", "files": ["App/LarderApp.swift", "Services/PantryService/PantryService.swift"]},
      {"text": "A recipe reserves what it needs from the pantry when it is planned, and gives it back when the plan is dropped.", "files": ["Services/PantryService/Reducers/PantryService.Reserve.swift"]},
      {"text": "Each screen is a component that reads the pantry and the planner through their services.", "files": ["Components/Week/Week.swift", "Components/Shelf/Shelf.swift"]}],
     "features": [
      {"title": "A shelf that counts", "text": "Every item on the shelf keeps its quantity and the date it runs out.", "files": ["Services/PantryService/Models/ShelfItem.swift"]},
      {"title": "Plans by the week", "text": "A week of meals is planned on one screen, each day with its recipes.", "files": ["Components/Week/Week.swift"]},
      {"title": "Shopping from the gaps", "text": "The shopping list is what the week's recipes need and the shelf lacks.", "files": ["Services/ListService/ListService.swift"]}]}
    """#

    static let folderExample = #"""
    {"sentences": [
      {"text": "This folder holds the pantry: the service that keeps what is on the shelf and the reducers that change it.", "files": ["Services/PantryService/PantryService.swift"]},
      {"text": "Reserving and releasing an item are events of its center, each answered by a reducer of its own.", "files": ["Services/PantryService/Reducers/PantryService.Reserve.swift", "Services/PantryService/Reducers/PantryService.Release.swift"]}]}
    """#

    static func system(_ rules: String, example: String) -> String {
        rules + "\n\nAn answer for another project, to copy the shape of and never the names or the words:\n" + example
    }

    static func user(project: String, digest: ProseDigest, what: String) -> String {
        "The project is \(project). The digest of its code:\n\n\(digest.text)\n\nWrite \(what) for \(project), citing only files the digest names."
    }

    static func retry(_ answer: String, problems: [String]) -> String {
        "\n\nYour last answer:\n\(answer)\n\nIt was refused:\n" + problems.prefix(12).map { "- " + $0 }.joined(separator: "\n") + "\n\nWrite the whole answer again, fixed."
    }

    static func schema(features: Bool) -> Data {
        let text: [String: Any] = ["type": "string"]
        let files: [String: Any] = ["type": "array", "items": text]
        let claim: [String: Any] = ["type": "object", "required": ["text", "files"], "properties": ["text": text, "files": files]]
        var properties: [String: Any] = ["sentences": ["type": "array", "items": claim]]
        var required = ["sentences"]
        if features {
            properties["features"] = ["type": "array", "items": ["type": "object", "required": ["title", "text", "files"],
                                                                 "properties": ["title": text, "text": text, "files": files]]]
            required.append("features")
        }
        let object: [String: Any] = ["type": "object", "required": required, "properties": properties]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
