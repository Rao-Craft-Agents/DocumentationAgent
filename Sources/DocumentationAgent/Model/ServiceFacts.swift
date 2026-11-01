//  WHAT: A Granite service or component as the documentation tells it: where it is declared, what it says it is, its
//        events and the reducer each names, the services it holds a relay to, its `@Agent`s, and, for a service, its rank.

import Foundation

struct ServiceFacts: Sendable {
    struct Event: Sendable {
        let event: String
        let reducer: String
        /// The reducer's declaration and the first sentence of its doc comment, when the walk found it.
        let path: String?
        let line: Int?
        let doc: String?
        /// The reducer's `reduce` and `effect`, by their numbers in the graph.
        let scopes: [Int]
        /// Where the center declares the event.
        let declared: Int
    }

    struct Agent: Sendable {
        let name: String
        let type: String
        let policy: String
        let run: Int?
    }

    let name: String
    let isComponent: Bool
    let scope: Int
    let path: String
    let line: Int
    let module: String
    let folder: String
    let what: String?
    let events: [Event]
    /// The services its code holds: `@Relay var`, a service-typed property.
    let relays: [String]
    /// The services it relays to or sends an event to: what its rank is read off.
    let reaches: [String]
    let rank: Int
    let agents: [Agent]
}
