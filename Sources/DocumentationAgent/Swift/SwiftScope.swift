//  WHAT: One declaration the walk found: what it is (a func, an init, a type, an extension, a computed var), its name
//        and parameters, the lines it spans, its doc comment, the scope it sits in and how it is flagged.

import Foundation

struct SwiftScope: Sendable {
    /// The kinds as the page's data writes them: func, init, deinit, subscript, var, struct, class, enum, actor,
    /// extension, protocol.
    static let kinds: [String: String] = ["func": "f", "init": "i", "deinit": "d", "subscript": "s", "var": "v", "struct": "S",
                                          "class": "C", "enum": "E", "actor": "A", "extension": "X", "protocol": "P"]
    static let typeKinds: Set<String> = ["S", "C", "E", "A", "P"]
    static let callableKinds: Set<String> = ["f", "i", "s"]
    static let requirementFlag = 1, operatorFlag = 2, localFlag = 4, oneLineFlag = 8

    var keyword: String
    var kind: String
    var name: String
    var params: [SwiftDeclaration.Param]
    var isOperator: Bool
    var mods: String
    var attrs: [String]
    /// The first unit of the declaration (an attribute, a modifier or its keyword), and of its keyword.
    var offset: Int
    var keywordOffset: Int
    /// The scope it is declared in, by its index in the file, or -1 at the top.
    var parent: Int
    /// Its `{`, as an offset and as a line and the column in that line; nil for a protocol's requirement.
    var braceOffset: Int?
    var braceLine: Int?
    var braceColumn: Int?
    /// Its `}`'s line and offset; nil while the walk has not closed it.
    var end: Int?
    var endOffset: Int?
    var isRequirement: Bool
    /// The line of its keyword, and of its first attribute line.
    var sig = 0
    var decl = 0
    /// Where its first line starts.
    var headOffset = 0
    /// The lines of its `///` doc comment, when it has one.
    var doc: ClosedRange<Int>?
    var flags = 0
    var cases: [String]?

    var isType: Bool { Self.typeKinds.contains(kind) }
    var isTypeOrExtension: Bool { isType || kind == "X" }
    var isCallable: Bool { Self.callableKinds.contains(kind) }
    var labels: [String] { params.map(\.label) }
    /// The name's last part: `Foo` for `extension Outer.Foo`.
    var simpleName: String { name.split(separator: ".").last.map(String.init) ?? name }
}
