//  WHAT: The site's front end, carried in the package: the page, its stylesheet and its scripts, generalized from Craft's
//        architecture companion. The literals are written by `scripts/embed-site.py` from `site-src/`.
//  PIN:  NO RESOURCE BUNDLE. A package Craft installs runs as one executable; the files are Swift string literals, and
//        `SiteAssetsTests` fails when a literal and its file in `site-src/` differ.

import Foundation

enum SiteAssets {
    /// The scripts the page loads, in its order; `ask.js` only when the site carries the orb.
    static func files(ask: Bool) -> [(name: String, text: String)] {
        [("app.css", css), ("core.js", core), ("folders.js", folders), ("explorer.js", explorer)] + (ask ? [("ask.js", Self.ask)] : []) + [("app.js", app)]
    }

    /// The page, titled for the project, with the orb's script when it carries one.
    static func page(title: String, ask: Bool) -> String {
        let escaped = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        return index.replacingOccurrences(of: "{{title}}", with: escaped)
            .replacingOccurrences(of: "<!--ask-->\n", with: ask ? "<script src=\"ask.js\"></script>\n" : "")
    }
}
