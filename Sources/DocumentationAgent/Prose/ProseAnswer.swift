//  WHAT: What the model answers when asked for prose: sentences, each with the files that show it, and for a README its
//        features, each a title, a sentence and its files. Decoded, checked, and only then written.

import Foundation

struct ProseAnswer: Codable, Sendable, Equatable {
    struct Claim: Codable, Sendable, Equatable {
        var text: String
        var files: [String]
    }

    struct Feature: Codable, Sendable, Equatable {
        var title: String
        var text: String
        var files: [String]
    }

    var sentences: [Claim]
    var features: [Feature]?
}
