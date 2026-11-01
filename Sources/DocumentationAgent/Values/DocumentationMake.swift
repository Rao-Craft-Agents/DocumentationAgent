import Foundation

/// What a call writes: the documentation of a codebase, one of three ways.
public enum DocumentationMake: String, Codable, Sendable, CaseIterable {
    /// `README.md`: what the project is, its features, how to build and test it, its structure and how it is built.
    case readme
    /// `Docs/`: the architecture, one page per top-level folder, a glossary of public types, how to build.
    case markdown
    /// `Docs/site/`: an interactive static site with a code explorer that opens from `file://`.
    case site
}
