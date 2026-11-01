import Foundation

/// Why a trail line or one of its steps cannot be walked.
struct TrailError: Error, Equatable, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
