import Foundation
import GraniteAgents

/// What a call answers: the files written, as absolute paths, and a few counts and sentences a model can relay.
public struct DocumentationResult: AgentAnswer, Equatable {
    /// The file to open first: the README, `Architecture.md`, or the site's `index.html`.
    public var path: String?
    /// Every file written.
    public var paths: [String]
    /// What was made: readme, markdown or site.
    public var make: String
    /// The site's address on disk, to open in a browser; nil for the other makes.
    public var open: String?
    /// How many source files were read, and how many of them are Swift.
    public var files: Int
    public var swift: Int
    /// The Granite services found, and the trails the site walks.
    public var services: Int
    public var trails: [String]
    /// One sentence each: what was left out and why, and what the model wrote.
    public var notes: [String]

    public init(path: String?, paths: [String], make: String, open: String?, files: Int, swift: Int, services: Int,
                trails: [String], notes: [String]) {
        self.path = path; self.paths = paths; self.make = make; self.open = open; self.files = files; self.swift = swift
        self.services = services; self.trails = trails; self.notes = notes
    }
}
