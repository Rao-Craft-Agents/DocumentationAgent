//  WHAT: Whether Swift files parse, by the toolchain's own parser (`swiftc -parse`): no SDK, no type checking,
//        a fraction of a second. What a call checks before anything lands; the turn's build checks the rest.
//  PIN:  A missing toolchain is not a failure of the code: with no `xcrun`, the check passes and says nothing.

import Foundation

enum SwiftParse {
    /// The compiler's error lines when any of `files` does not parse; nil when all do.
    static func check(_ files: [URL]) throws -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "-parse"] + files.map(\.path)
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n").filter { $0.contains("error:") }.prefix(12).map(String.init)
        return lines.isEmpty ? String(text.prefix(2_000)) : lines.joined(separator: "\n")
    }
}
