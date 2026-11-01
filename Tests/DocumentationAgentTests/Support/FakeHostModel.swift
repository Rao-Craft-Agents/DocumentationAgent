import Foundation
import GraniteAgents

/// A host model that answers the next of its scripted replies to each ask, the last one again when it runs out, and
/// keeps what it was asked.
final class FakeHostModel: AgentHostModel, @unchecked Sendable {
    struct Ask { let system: String; let user: String }

    private let lock = NSLock()
    private var replies: [Data]
    private var kept: [Ask] = []

    init(_ replies: [Data]) { self.replies = replies }

    var asked: [Ask] { lock.withLock { kept } }

    func object(schema: Data, system: String, user: String, maxTokens: Int, seconds: Double) async throws -> Data {
        lock.withLock {
            kept.append(Ask(system: system, user: user))
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
    }

    func text(system: String, user: String, maxTokens: Int, seconds: Double) async throws -> String { "" }
}
