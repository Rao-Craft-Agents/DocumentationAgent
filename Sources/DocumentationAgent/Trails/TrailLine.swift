//  WHAT: A trail as a call writes it, one line: a name, a colon, then the steps the walk takes, each a declaration as
//        the code names it, joined by arrows.
//
//            save a recipe: RecipeEditor.save → RecipeService.Save → PantryService.Reserve
//
//        `->` reads the same as `→`. A step is `Type.member`, `Type.init`, `Type.member(label:)`, a reducer
//        `Service.Reducer` (walked as its reduce and its effect), or a bare name the project has once.

import Foundation

struct TrailLine: Sendable, Equatable {
    let name: String
    let steps: [String]

    static let maxSteps = 14

    /// The line read, or the reason it cannot be.
    static func parse(_ line: String) -> Result<TrailLine, TrailError> {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.firstIndex(of: ":") else {
            return .failure(TrailError("`\(text)` is not `name: Step → Step`: it has no colon"))
        }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure(TrailError("`\(text)` names no trail before its colon")) }
        let body = text[text.index(after: colon)...].replacingOccurrences(of: "->", with: "→")
        let steps = body.split(separator: "→").map { $0.trimmingCharacters(in: .whitespaces) }
        if steps.contains(where: \.isEmpty) { return .failure(TrailError("the trail `\(name)` has an empty step between two arrows")) }
        guard steps.count >= 2 else { return .failure(TrailError("the trail `\(name)` has one step; a trail walks from one declaration to the next")) }
        guard steps.count <= maxSteps else { return .failure(TrailError("the trail `\(name)` has \(steps.count) steps; split it in two of at most \(maxSteps)")) }
        return .success(TrailLine(name: name, steps: steps))
    }
}
