import GraniteAgents

/// The network agent's place in Granite's roster: an app that links this package finds the `network` agent by this
/// record, with nothing listed by hand.
@used @section("__DATA_CONST,__granite")
let networkRecord: GraniteRoster.Record = { GraniteRoster.record(NetworkAgent.self) }
