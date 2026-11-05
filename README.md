# DocumentationAgent

Ask for a README, Markdown docs or a browsable site, and `docs` writes them from the project's own code, so the next
person, and the next model, starts from the code rather than a guess. The site opens from the project folder with no
server: a page for every folder, every file with its declarations, search, and an Explorer that follows the calls and
the [Granite](https://github.com/riteshpakala/Granite) flows through the code. It is the companion
[Craft](https://github.com/riteshpakala/Craft) keeps of its own architecture, made for any Swift codebase.

## What you can ask

```
$docs a site for this project, with a trail for saving a recipe, and the ask orb
$docs a README for Larder, a pantry and recipe planner for iOS and macOS, under the MIT licence
$docs Markdown docs for the Services, Components and Shared folders
```

Craft's model writes the call; it shows on Craft's agent map, and the files it names are re-indexed with the turn.

## What you get

- **A README.** What the project is and its features, its requirements, how to build and test it, its folder tree with
  a line each, how it is built, and its licence, with a `LICENSE` file when you name one and the project has none.
- **Markdown docs.** An architecture page with the modules in dependency order, a page for each top-level folder led by
  what its code says of itself, a glossary of its types and a page on building it.
- **A site with a code explorer.** A page for each folder, every file's source with line anchors and its declarations,
  calls both ways, search by name, signature or pasted body, and every Markdown file of the project, rendered.
- **Trails through the code.** Walks you name, such as saving a recipe from the editor through the services it
  reaches, or ones it derives from the app's own flows: launch, then each service's events.
- **An ask orb, when you want one.** It answers questions about the code from the site's own data, through a chat
  completions API with a key you add yourself. No call ever writes a key.

## How it works

- It reads every code and Markdown file under the folders you name, and the project's manifests: `Package.swift`, read
  as text and never run, the Xcode project and its schemes, and `package.json`. Swift is walked for declarations,
  calls, services and flows; files in other languages get their pages and search.
- Calls are matched by name and argument labels, not by a compiler, and each is marked exact, likely or ambiguous.
- The model writes only a README's opening and features and each folder page's overview, from a digest of the code,
  each sentence citing the files it rests on. An answer that fails a check is asked again with every problem. With no
  model, everything else is still written, and the answer says what was left out.
- Every file is staged, then moved into the project together, whole or not at all.

## Works well with

`docs` writes down what the other Rao Craft Agents built, from the code itself: the services and pages `granite`
wrote, with their events and relays, drawn in the Explorer as the flows between them and ranked by what they relay
to. `screenshots` captures the app's screens and writes a README table of them.

## Get it

In Craft, install Docs from the Agent Store, or run
`craft agents add https://github.com/Rao-Craft-Agents/DocumentationAgent.git`, then say `$docs` in a request.

## Requirements

- A Mac on macOS 14 or later.
- The site opens in a browser from `file://`, with no server.
- The ask orb calls a chat completions API (Mistral's, or any compatible endpoint) only with a key you write into
  `Docs/site/local/ask.js`; the site's `.gitignore` keeps that folder out of the repository.
- MIT licensed.

## For developers

What a call takes and answers, what each make writes, the site's routes and how the documentation is made are in the
[reference](Docs/Reference.md). The agent standard it follows is Granite's
[granite-agent/1](https://github.com/riteshpakala/Granite/blob/main/Schema/GraniteAgent.md), and how it is tested is
[TESTING.md](TESTING.md).
