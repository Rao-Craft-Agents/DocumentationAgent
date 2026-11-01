//  WHAT: What a declaration does, said from the graph rather than a comment: the state a reducer writes, the events and
//        relays it sets off, the calls it makes the matcher is sure of. What a trail's note and a reducer's row say
//        when the code has no doc comment.

import Foundation

struct CodeFacts {
    let graph: CallGraph

    static let flowKinds: Set<String> = ["event", "relay", "own", "agent", "frames", "reply", "handler"]
    /// A reducer's write to its state: `state.posts = …`, `state.count += 1`, `state.items.append(…)`.
    private static let stateWrite = Pattern(#"\bstate\.(\w+)\s*(?:[-+*/]?=(?!=)|\.(?:append|insert|remove\w*|merge|update\w*)\(|\[[^\]\n]*\]\s*[-+*/]?=(?!=))"#)

    /// The state fields a reducer's `reduce` or `effect` writes, in the order it first writes them.
    func writes(_ g: Int) -> [String] {
        let scope = graph.scopes[g]
        guard ["reduce", "effect"].contains(scope.name), let open = scope.braceOffset, let close = scope.endOffset else { return [] }
        let body = graph.blankStrings[graph.fileOf[g]].substring(with: NSRange(location: open, length: close - open))
        var written: [String] = []
        for m in Self.stateWrite.matches(body) {
            if let field = m.group(1, in: body), !written.contains(field) { written.append(field) }
        }
        return written
    }

    /// The name a flow's target goes by: a reducer by its type, anything else by its qualified name.
    func named(_ g: Int) -> String {
        if ["reduce", "effect"].contains(graph.scopes[g].name), let parent = graph.parentOf(g) { return graph.qualified[parent] }
        return graph.qualified[g]
    }

    /// What `g` does, as clauses: "writes `state.a` and `state.b`", "sets off `X.Boot` (event)", "calls `Y.load`".
    func clauses(_ g: Int, edges out: [CallGraph.Edge]) -> [String] {
        var said: [String] = []
        let written = writes(g)
        if !written.isEmpty {
            said.append("writes " + ProjectModel.list(written.prefix(5).map { "`state.\($0)`" } + (written.count > 5 ? ["\(written.count - 5) more"] : [])))
        }
        let flows = out.filter { $0.via.map(Self.flowKinds.contains) == true }
        if !flows.isEmpty {
            var seen: [String] = []
            for e in flows {
                let item = "`\(named(e.target))` (\(e.via!))"
                if !seen.contains(item) { seen.append(item) }
            }
            said.append("sets off " + ProjectModel.list(Array(seen.prefix(4)) + (seen.count > 4 ? ["\(seen.count - 4) more"] : [])))
        } else {
            let calls = out.filter { $0.via == nil && $0.tier == 0 }
            if !calls.isEmpty { said.append("calls " + ProjectModel.list(calls.prefix(4).map { "`\(graph.qualified[$0.target])`" })) }
        }
        return said
    }

    /// The edges out of each declaration, read once.
    static func outgoing(_ graph: CallGraph) -> [Int: [CallGraph.Edge]] {
        var out: [Int: [CallGraph.Edge]] = [:]
        for edge in graph.edges { out[edge.source, default: []].append(edge) }
        return out
    }
}
