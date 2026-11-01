import Foundation

/// A licence a README names and, when the project has no `LICENSE`, writes: its SPDX identifier.
public enum DocumentationLicense: String, Codable, Sendable, CaseIterable {
    case mit = "MIT"
    case apache = "Apache-2.0"
    case bsd = "BSD-3-Clause"
    case isc = "ISC"
}
