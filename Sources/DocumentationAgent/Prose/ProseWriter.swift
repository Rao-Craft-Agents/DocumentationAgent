//  WHAT: The asks for prose, on the host's model: a README's opening and features, a folder's overview. Each ask is
//        narrow and bounded (a few hundred tokens), decoded, checked with `ProseCheck`, and asked again with every
//        problem said, up to the call's rounds. An answer that never passes is left out, and the note says why.
//  PIN:  NO MODEL, NO PROSE. Without a model the sections are left out and said so in a note; nothing is ever filled
//        with placeholder text, and nothing the model writes is parsed as code.

import Foundation
import GraniteAgents

struct ProseWriter: Sendable {
    let model: (any AgentHostModel)?
    let rounds: Int
    let note: @Sendable (String) -> Void

    struct Outcome: Sendable {
        let answer: ProseAnswer?
        /// Why there is none, as the end of a sentence.
        let why: String?
    }

    func opening(_ project: String, digest: ProseDigest, features: Bool) async -> Outcome {
        await ask(system: ProsePrompt.system(features ? ProsePrompt.readmeRules : ProsePrompt.readmeOnlyOpening, example: ProsePrompt.readmeExample),
                  user: ProsePrompt.user(project: project, digest: digest, what: features ? "the README's opening sentences and its features" : "the README's opening sentences"),
                  digest: digest, sentences: 2...4, features: features ? 3...7 : nil, maxTokens: features ? 700 : 400, seconds: features ? 150 : 90)
    }

    func overview(_ project: String, folder: String, digest: ProseDigest) async -> Outcome {
        await ask(system: ProsePrompt.system(ProsePrompt.folderRules, example: ProsePrompt.folderExample),
                  user: ProsePrompt.user(project: project, digest: digest, what: "the overview of \(folder)/"),
                  digest: digest, sentences: 1...3, features: nil, maxTokens: 350, seconds: 75)
    }

    private func ask(system: String, user: String, digest: ProseDigest, sentences: ClosedRange<Int>, features: ClosedRange<Int>?,
                     maxTokens: Int, seconds: Double) async -> Outcome {
        guard let model else { return Outcome(answer: nil, why: "the host offers no model") }
        var prompt = user
        var last = ""
        for round in 1...max(1, rounds) {
            if Task.isCancelled { return Outcome(answer: nil, why: "the call was cancelled") }
            let data: Data
            do {
                data = try await model.object(schema: ProsePrompt.schema(features: features != nil), system: system, user: prompt,
                                              maxTokens: maxTokens, seconds: seconds)
            } catch {
                last = "\(error)"
                note("round \(round): the model gave no answer")
                continue
            }
            let raw = String(decoding: data, as: UTF8.self)
            guard var answer = try? JSONDecoder().decode(ProseAnswer.self, from: data) else {
                last = "its answer is not the JSON asked for"
                prompt = user + ProsePrompt.retry(String(raw.prefix(1_500)), problems: ["the answer is not one JSON object with `sentences`" + (features == nil ? "" : " and `features`")])
                continue
            }
            let problems = ProseCheck.problems(&answer, digest: digest, sentences: sentences, features: features)
            if problems.isEmpty { return Outcome(answer: answer, why: nil) }
            last = problems[0]
            note("round \(round): \(problems.count) to fix — \(problems[0])")
            prompt = user + ProsePrompt.retry(String(raw.prefix(1_500)), problems: problems)
        }
        return Outcome(answer: nil, why: "the model's answer did not pass its checks in \(rounds) round\(rounds == 1 ? "" : "s") (the last: \(last))")
    }
}
