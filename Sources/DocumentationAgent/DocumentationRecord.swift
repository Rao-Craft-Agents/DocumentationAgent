import GraniteAgents

/// The docs agent's place in Granite's roster: an app that links this package finds the `docs` agent by this record,
/// with nothing listed by hand.
@used @section("__DATA_CONST,__granite")
let documentationRecord: GraniteRoster.Record = { GraniteRoster.record(DocumentationAgent.self) }
