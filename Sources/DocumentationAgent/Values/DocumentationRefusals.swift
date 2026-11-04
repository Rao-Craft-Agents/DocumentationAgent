import Foundation
import GraniteAgents

/// Documentation's refusals as the answer standard (granite-answer/1) counts them: each of its own a fix the call can make.
extension DocumentationError: AgentRefusing {
    public var refusal: AgentRefusal { AgentRefusal(.call, description) }
}

/// Swift this agent wrote that did not parse is `parse`; a file it could not write is the host's.
extension AgentFilesError: AgentRefusing {
    var refusal: AgentRefusal {
        switch self {
        case .unparsed: return AgentRefusal(.parse, description)
        case .unwritable: return AgentRefusal(.host, description)
        }
    }
}
