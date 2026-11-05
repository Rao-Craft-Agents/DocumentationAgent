# DocumentationAgent reference

How the `docs` agent is found, what a call takes and answers, what each make writes, how the documentation is made,
and how to test it. What it is for is in the [README](../README.md); the agent standard it follows is Granite's
[granite-agent/1](https://github.com/riteshpakala/Granite/blob/main/Schema/GraniteAgent.md).

## How an app finds it

DocumentationAgent is a `GraniteAgentPackage`, and it carries a record in its binary:

```swift
@used @section("__DATA_CONST,__granite")
let documentationRecord: GraniteRoster.Record = { GraniteRoster.record(DocumentationAgent.self) }
```

In Craft, install it from the Agent Store or with
`craft agents add https://github.com/Rao-Craft-Agents/DocumentationAgent.git`, then say `$docs` in a request:

```
$docs a site for this project, with a trail for saving a recipe, and the ask orb
```

The model writes the call; the call shows on Craft's agent map as `docs-1`, and the files it names are re-indexed with
the turn.

## What a call takes and answers

| Field | | |
|---|---|---|
| `make` | required | `readme`, `markdown` or `site` |
| `into` | optional | where the files go, from the project's root; the root for a README, `Docs` for Markdown, `Docs/site` for a site |
| `sources` | optional | the folders to read; the whole project when left out |
| `title` | optional | the project's name; read off its `Package.swift`, Xcode project or `package.json` when left out |
| `tagline` | optional | one line under the title, in the person's words |
| `features` | optional | the README's feature lines, when the person gives them |
| `license` | optional | `MIT`, `Apache-2.0`, `BSD-3-Clause` or `ISC`: named by the README, written as `LICENSE` when the project has none |
| `trails` | optional | walks the site's Explorer follows, one a line: `save a recipe: RecipeEditor.save → RecipeService.Save → PantryService.Reserve` |
| `ask` | optional | `true` adds the ask orb to the site |
| `rounds` | optional | how many times the model's prose may be asked again after it fails a check; 3 when left out |
| `directory` | the host's | the folder the host works in; a host fills it and does not show it to a model. A call with none uses the host's own folder |

The answer is a `DocumentationResult`: every file written (`path`, `paths`, absolute), the site's `file://` address,
how many files and Swift files were read, the services found, the trails walked, and a sentence for anything left out.

## What each make writes

| Make | Files |
|---|---|
| `readme` | `README.md`: what the project is and its features, its requirements, how to build and test it (each Xcode scheme for its platform, the Swift packages, the `package.json` scripts), its folder tree with a line each, how it is built (services, components, packages, targets), and its licence; `LICENSE` when one is named and the project has none |
| `markdown` | `Docs/Architecture.md` (the modules in dependency order, from the manifests and every file's imports; the targets; the folders; the services by rank; the components; the calls), one page per top-level folder led by what its code says of itself, `Glossary.md` (every type outside a private scope, one line each) and `Building.md` |
| `site` | `Docs/site/`: `index.html`, its stylesheet and scripts, `data.js` and `explorer/*.js` (classic scripts, since `fetch` is refused on `file://`), and a `.gitignore` that keeps `local/` out of the repository |

### The site

| Route | Draws |
|---|---|
| `#/` | the project: its folders, its services by rank and its components, its Xcode targets and packages, how to build and test it, its docs |
| `#/<folder>` | a folder: what its code says it is (its root type's WHAT or doc comment, its service, its package's comment, its README), else what it holds; its folders, its files, its services, where the trails pass |
| `#/<file>[:line]` | a file in the Explorer: its source verbatim with line anchors, its declarations, and for the selected one its signature, doc comment, trail notes and calls both ways |
| `#/explorer` | the Explorer: find, the trails, the services by rank with their events, the tree, the source |
| `#/trail/<id>/<n>` | a step of a trail, each entry saying how the one before reaches it |
| `#/find/<text>` | a declaration by name, `Type.method`, a signature line or a pasted body |
| `#/file/<doc>.md` | a Markdown file of the project, rendered, with its headings beside it |

The ask orb, when asked for, answers questions about the code with four tools over the site's own data (find a
declaration, read one, search the text, read a file). It calls a chat completions API (Mistral's, or any compatible
endpoint) only with a key the person writes into `Docs/site/local/ask.js`:

```js
window.DOCS_ASK = { provider: "mistral", model: "mistral-large-latest", key: "…" };
```

No call ever writes a key, and the site's `.gitignore` keeps `local/` out of the repository.

## How the documentation is made

| Step | What |
|---|---|
| Read | every code file and Markdown file under the folders named, in path order; a file over 400 KB, or past 24 MB in all, is left out and said; build products, dependencies, editor state and an earlier site are never read |
| Manifests | `Package.swift` (read as text, never run), the Xcode project (`project.pbxproj` and its shared schemes), `package.json`, and other tools' files |
| Walk | every Swift file through a lexer (strings, raw and multi-line, interpolation, `#/…/#` regex literals, nested comments) and a brace walk: types, extensions, functions, inits, subscripts, computed vars, protocol requirements, enum cases. A file the lexer cannot finish keeps its text and declares nothing; an `#if` that opens a brace twice still walks |
| Calls | each call matched by name and argument labels, not a compiler: exact (one fits and its type is named), likely (the name is unique), ambiguous (two to eight fit). A receiver whose type the declarations name reaches that type's member; a protocol, every conformer; a type the project does not declare, nothing. Of several, the caller's own module is preferred |
| Granite | each `GraniteService` and `GraniteComponent`, its center's `@Event`s and the reducer each names, its `@Relay`s and `@Agent`s, and every flow: an event sent, a relay, an `@Agent` run, its frames, a ticket's reply, a handler the root installed. A service's rank is one above the highest service it relays to or sends an event to; a circle is cut and said |
| Trails | the call's own lines, every step resolved or refused with its reason; else derived: boot, from the `@main` type through every event and relay it sets off, then each service's events |
| Prose | the model writes only the README's opening and features and a folder page's overview, from a digest of the code, each sentence citing files the digest named; an answer is checked (length, citations, no markup, no placeholder, no marketing, nothing copied from the worked example) and asked again with every problem, up to `rounds` |
| Write | every file staged, then moved into the project together, whole or not at all |

With no model, everything but the prose is written, and the answer says what was left out. The site holds no model
prose, so the same tree writes the same bytes.

## Testing

```
swift test                    # the record, the schema, the lexer and walk, the graph, the trails, each make, the assets
DOCS_BUILD=1 swift test       # all three makes on a copy of Loom and of this package, each site drawn in headless Chrome
```

`python3 -I scripts/embed-site.py` regenerates `Sources/DocumentationAgent/Site/SiteAssets+*.swift` from `site-src/`;
`SiteAssetsTests` fails when a literal and its file differ.
