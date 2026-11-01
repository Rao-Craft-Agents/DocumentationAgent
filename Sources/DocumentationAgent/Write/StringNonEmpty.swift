import Foundation

extension String {
    /// The string, or nil when it is empty.
    var nonEmpty: String? { isEmpty ? nil : self }
}
