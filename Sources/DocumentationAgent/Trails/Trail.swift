//  WHAT: A walk through the code, resolved: steps of declarations in the order they run, each entry with a note read off
//        the code and the hop that reaches it from an earlier entry: the Granite flow or the call the graph holds.

import Foundation

struct Trail: Sendable {
    struct Entry: Sendable {
        let scope: Int
        let id: String
        let note: String
        /// Where the note is read from: doc (the declaration's doc comment), WHAT (its file's), code (its declaration).
        let cite: String
        let line: Int
        /// How it is reached: the flow or call's kind, then the step and entry it comes from; nil for the first.
        var hop: (kind: String, step: Int, entry: Int)?
    }

    struct Step: Sendable {
        let n: Int
        let title: String
        var entries: [Entry]
    }

    let id: String
    let mark: String
    let title: String
    let subtitle: String
    let say: String
    var steps: [Step]

    var json: JSONValue {
        .object([
            ("id", .string(id)), ("kind", .string("trail")), ("mark", .string(mark)), ("title", .string(title)), ("subtitle", .string(subtitle)),
            ("say", .string(say)),
            ("steps", .array(steps.map { step in
                .object([("n", .int(step.n)), ("title", .string(step.title)), ("entries", .array(step.entries.map { e in
                    var pairs: [(String, JSONValue)] = [("scope", .int(e.scope)), ("id", .string(e.id)), ("note", .string(e.note)),
                                                         ("cite", .string(e.cite)), ("line", .int(e.line))]
                    if let hop = e.hop {
                        pairs.append(("hop", hop.kind == "sent" ? .array([.string("sent")]) : .array([.string(hop.kind), .int(hop.step), .int(hop.entry)])))
                    }
                    return .object(pairs)
                }))])
            })),
        ])
    }

    /// How many of its hops are Granite flows.
    var flows: Int { steps.reduce(0) { $0 + $1.entries.filter { e in ["event", "relay", "own", "agent", "frames", "reply", "handler"].contains(e.hop?.kind ?? "") }.count } }
}
