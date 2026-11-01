/* The documentation site — what every view shares: an escaping template tag, formatting, indexes over the generated
   data (data.js), links into this page and into the editor, the route parser, settings, storage, the tooltip and the
   toast, and for the views that keep their own elements, a DOM builder and a highlighter. Generalized from Craft's
   architecture companion (Docs/site/core.js) for any codebase.
   PIN: every route is a folder of the project, a file of it, or one of four views: #/explorer, #/trail/…, #/find/…
   and #/file/<doc>.md. A top-level folder that shares a view's name is reached as #/./<name>. */
(() => {
  'use strict';
  const Arch = (window.Arch = window.Arch || {});
  const D = (Arch.data = window.DOCS_SITE || null);

  // MARK: - Templates

  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ESC[c]);
  class Raw { constructor(s) { this.s = s; } toString() { return this.s; } }
  const raw = (s) => new Raw(String(s == null ? '' : s));
  // `false` and null render as nothing (conditional content); `true` as "true" (aria-pressed, aria-selected).
  const out = (v) => (v == null || v === false ? '' : v === true ? 'true' : v instanceof Raw ? v.s : Array.isArray(v) ? v.map(out).join('') : esc(v));
  /** Interpolations are escaped unless they are `raw()` or another `html` result. */
  function html(strings, ...values) {
    let s = strings[0];
    values.forEach((v, i) => { s += out(v) + strings[i + 1]; });
    return new Raw(s);
  }
  Object.assign(Arch, { esc, raw, html, Raw });
  /** `map[key]` when the map holds it itself: a name from the code (`constructor`, `toString`) never reads Object's own. */
  const own = (Arch.own = (map, key) => (map && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined));

  // MARK: - Formatting

  const fmt = (Arch.fmt = {
    n: (v) => (typeof v === 'number' && isFinite(v) ? v.toLocaleString('en-US') : v == null ? '–' : String(v)),
    k: (v) => (typeof v !== 'number' ? '–' : v >= 10000 ? (v / 1000).toFixed(0) + 'k' : v >= 1000 ? (v / 1000).toFixed(1) + 'k' : String(v)),
    plural: (n, one, many) => `${fmt.n(n)} ${n === 1 ? one : many || one + 's'}`,
    clip: (t, n) => { t = String(t == null ? '' : t).replace(/\s+/g, ' ').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t; },
  });

  /** Backticks become code, **x** bold. Escapes first. */
  const inline = (text) => esc(text).replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
  Arch.inline = inline;

  // MARK: - Indexes

  const idx = (Arch.idx = {});
  function buildIndexes() {
    idx.files = new Map(D.files.map((f) => [f.path, f]));
    idx.docs = D.docs || {};
    idx.types = D.types || {};
    idx.services = new Map((D.services || []).concat(D.components || []).map((s) => [s.name, s]));
    idx.trails = D.trails || [];
  }
  const slug = (Arch.slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''));
  /** Where a type is declared: its top-level declaration first, else a nested one. */
  idx.typeLocation = (name) => {
    const base = String(name).split('.')[0].replace(/<.*$/, '');
    const hits = own(idx.types, base) || [];
    return hits.find((h) => !h.nested && h.kind !== 'extension') || hits[0] || null;
  };

  // MARK: - Settings and storage

  const KEY = 'docs.' + slug((D && D.meta && D.meta.title) || 'site') + '.';
  const store = (Arch.store = {
    get(key, fallback) { try { const v = localStorage.getItem(KEY + key); return v == null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
    set(key, value) { try { localStorage.setItem(KEY + key, JSON.stringify(value)); } catch (e) { /* storage is a convenience */ } },
    remove(key) { try { localStorage.removeItem(KEY + key); } catch (e) { /* ignore */ } },
  });
  /** The project's folder, from this page's own address when it is opened from disk: the address less the site's folder. */
  const pageRoot = () => {
    if (location.protocol !== 'file:' || !D) return null;
    const path = decodeURIComponent(location.pathname).replace(/\/[^/]*$/, '');
    const site = '/' + String(D.meta.site || '').replace(/^\/+|\/+$/g, '');
    return site !== '/' && path.endsWith(site) ? path.slice(0, path.length - site.length) || '/' : null;
  };
  Arch.settings = Object.assign({ scheme: 'vscode', root: null }, store.get('settings', {}));
  Arch.settings.pageRoot = pageRoot();
  if (!Arch.settings.root) Arch.settings.root = Arch.settings.pageRoot;

  // MARK: - Links

  const editorHref = (Arch.editorHref = (path, line) => {
    const root = Arch.settings.root;
    if (!root || !path) return null;
    const full = root.replace(/\/$/, '') + '/' + path;
    if (Arch.settings.scheme === 'xcode') return 'xed://' + encodeURI(full) + (line ? '?line=' + line : '');
    return `${Arch.settings.scheme}://file${encodeURI(full)}${line ? ':' + line : ''}`;
  });
  const ext = (path, line) => {
    const href = editorHref(path, line);
    return href ? html`<a class="ext" href="${href}" title="Open in the editor" aria-label="Open ${path}${line ? ' at line ' + line : ''} in the editor">↗</a>` : '';
  };
  const VIEWS = new Set(['explorer', 'trail', 'find', 'file']);
  const query = (q) => {
    const pairs = Object.entries(q || {}).filter(([, v]) => v != null && v !== '');
    return pairs.length ? '?' + pairs.map(([k, v]) => k + '=' + encodeURIComponent(v)).join('&') : '';
  };
  /** What the address must escape in a free tail, a declaration or a search: only what would break the route. */
  const escapeTail = (t) => String(t).replace(/%/g, '%25').replace(/\?/g, '%3F').replace(/#/g, '%23').replace(/ /g, '%20').replace(/\n/g, '%0A');
  const encodePath = (path) => String(path).split('/').map(encodeURIComponent).join('/');
  /** A path as the address writes it: a top-level folder that shares a view's name is written after `./`. */
  const routed = (path) => (VIEWS.has(String(path).split('/')[0]) ? './' : '') + encodePath(path);
  /** Every place the site has, as the address writes it: a folder, a file, a doc, the Explorer, a trail, a search. */
  const href = (Arch.href = {
    folder: (path, q) => (!path || path === '.' ? '#/' : '#/' + routed(path)) + query(q),
    file: (path, at) => (own(idx.docs, path) ? '#/file/' + encodePath(path) : '#/' + routed(path)) + (at ? ':' + escapeTail(at) : ''),
    doc: (path) => '#/file/' + encodePath(path),
    explorer: () => '#/explorer',
    trail: (id, n, k) => '#/trail/' + encodeURIComponent(id) + (n ? '/' + n : '') + (k ? ';n=' + k : ''),
    find: (text) => '#/find/' + escapeTail(text),
  });
  const fileHref = (path, line) => href.file(path, line);

  const link = (Arch.link = {
    ext,
    fileHref,
    file(path, line, label) {
      return html`<a class="ref" href="${fileHref(path, line)}">${label || path + (line ? ':' + line : '')}</a>${ext(path, line)}`;
    },
    type(name, label) {
      const hit = idx.typeLocation(name);
      if (hit) return html`<a class="ref type" href="${fileHref(hit.path, hit.line)}" title="${hit.kind} ${name} · ${hit.path}:${hit.line}">${label || name}</a>${ext(hit.path, hit.line)}`;
      return html`<code>${label || name}</code>`;
    },
    folder(path, label) { return html`<a class="ref" href="${href.folder(path)}">${label || (path === '.' ? D.meta.title : path.split('/').pop())}</a>`; },
    service(name) { const s = idx.services.get(name); return s ? html`<a class="ref mono" href="${fileHref(s.path, s.line)}">${name}</a>` : html`<code>${name}</code>`; },
    path(path) {
      if (idx.files.has(path) || own(idx.docs, path)) return link.file(path);
      return html`<span class="mono">${path}</span>${ext(path)}`;
    },
  });

  // MARK: - Markdown, as the site reads a project's docs

  /** Doc comments and notes: paragraphs, `-` lists with indented continuations, and fenced code. */
  function md(text) {
    if (!text) return raw('');
    const parts = String(text).replace(/\r/g, '').split(/^```[^\n]*\n([\s\S]*?)\n?```[ \t]*$/m);
    return raw(parts.map((part, i) => (i % 2
      ? `<pre class="code">${part.split('\n').map((line) => Arch.highlightHTML(line)).join('\n')}</pre>`
      : prose(part))).join(''));
  }
  function prose(text) {
    return text.split(/\n\s*\n/).map((block) => {
      let htmlOut = '', para = [], items = null;
      const flushPara = () => { if (para.length) { htmlOut += `<p>${inline(para.join(' '))}</p>`; para = []; } };
      const flushList = () => { if (items) { htmlOut += '<ul>' + items.map((i) => `<li>${inline(i)}</li>`).join('') + '</ul>'; items = null; } };
      block.split('\n').forEach((line) => {
        if (/^\s*[-*•] /.test(line)) { flushPara(); items = items || []; items.push(line.replace(/^\s*[-*•] /, '').trim()); }
        else if (items && /^\s{2,}\S/.test(line)) items[items.length - 1] += ' ' + line.trim();
        else { flushList(); if (line.trim()) para.push(line.trim()); }
      });
      flushPara(); flushList();
      return htmlOut;
    }).join('');
  }
  Arch.md = md;

  /** A link in a doc, resolved against the doc's folder: a doc of the project opens here, a file or folder of it opens
   *  on its page, the web opens beside the page. */
  function resolve(base, target) {
    const parts = (base && base !== '.' ? base.split('/') : []);
    String(target).split('/').forEach((p) => { if (p === '..') parts.pop(); else if (p && p !== '.') parts.push(p); });
    return parts.join('/');
  }
  const siteDepth = () => String((D && D.meta.site) || '').split('/').filter(Boolean).length;
  function docLink(label, url, base) {
    if (/^(https?:|mailto:)/.test(url)) return `<a class="ref" href="${esc(url)}" target="_blank" rel="noopener">${label}</a>`;
    if (/^#/.test(url)) return `<a class="ref" href="#" data-action="scroll-to" data-target="doc-${esc(url.slice(1))}">${label}</a>`;
    const [file, anchor] = url.split('#');
    const path = resolve(base, decodeURIComponent(file));
    if (own(idx.docs, path)) return `<a class="ref" href="${esc(href.doc(path))}">${label}</a>`;
    if (idx.files.has(path)) return `<a class="ref" href="${esc(href.file(path))}">${label}</a>`;
    if (own(D.folders, path.replace(/\/$/, ''))) return `<a class="ref" href="${esc(href.folder(path.replace(/\/$/, '')))}">${label}</a>`;
    return `<span class="ref" title="${esc(path)}${anchor ? '#' + esc(anchor) : ''}">${label}</span>`;
  }
  /** An image in a doc: one of the project's, drawn from its place beside the site; one on the web, named, never
   *  fetched, so the site makes no request a reader did not ask for. */
  function docImage(alt, url, base) {
    if (/^(https?:|data:)/.test(url)) return `<span class="doc-image">[image: ${esc(alt || url)}]</span>`;
    const path = resolve(base, decodeURIComponent(url.split('#')[0]));
    return `<img src="${esc('../'.repeat(siteDepth()) + path.split('/').map(encodeURIComponent).join('/'))}" alt="${esc(alt)}" loading="lazy">`;
  }
  const docInline = (text, base) => {
    const images = [];
    const held = String(text).replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (m, alt, url) => { images.push(docImage(alt, url, base)); return '\u0000' + (images.length - 1) + '\u0000'; });
    return inline(held)
      .replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)/g, (m, label, url) => docLink(label, url.replace(/&amp;/g, '&'), base))
      .replace(/&lt;(https?:\/\/[^\s&]+)&gt;/g, (m, url) => docLink(url, url, base))
      .replace(/\u0000(\d+)\u0000/g, (m, i) => images[+i]);
  };
  const docSlug = (t) => String(t).toLowerCase().replace(/`/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  /** A Markdown doc of the project, as its page reads it: headings (the first `# ` is the page's title, said by the
   *  page), paragraphs, `-` and `1.` lists, pipe tables, fenced code, quotes, images and links. HTML in the doc is
   *  shown as text, never run. */
  function doc(text, base) {
    const parts = String(text || '').replace(/\r/g, '').split(/^```[^\n]*\n([\s\S]*?)\n?```[ \t]*$/m);
    return raw(parts.map((part, i) => (i % 2
      ? `<pre class="code">${part.split('\n').map((line) => Arch.highlightHTML(line)).join('\n')}</pre>`
      : docBlocks(part, i === 0, base))).join(''));
  }
  function docBlocks(text, first, base) {
    const blocks = [];
    let para = [], list = null, table = null, quote = null, titled = !first;
    const flush = () => {
      if (para.length) { blocks.push(`<p>${docInline(para.join(' '), base)}</p>`); para = []; }
      if (list) { blocks.push(`<${list.tag}>${list.items.map((item) => `<li>${docInline(item, base)}</li>`).join('')}</${list.tag}>`); list = null; }
      if (table) { blocks.push(docTable(table, base)); table = null; }
      if (quote) { blocks.push(`<blockquote>${docInline(quote.join(' '), base)}</blockquote>`); quote = null; }
    };
    for (const line of text.split('\n')) {
      const heading = /^(#{1,6})\s+(.*)$/.exec(line);
      const item = /^\s*([-*+]|\d+\.)\s+(.*)$/.exec(line);
      if (heading) {
        flush();
        if (heading[1].length === 1 && !titled) { titled = true; continue; }
        const level = Math.min(Math.max(heading[1].length, 2), 4);
        blocks.push(`<h${level} class="doc-h" id="doc-${docSlug(heading[2])}">${docInline(heading[2].replace(/\s+#+\s*$/, ''), base)}</h${level}>`);
      } else if (/^\s*\|/.test(line)) {
        if (para.length || list || quote) flush();
        (table = table || []).push(line);
      } else if (/^\s*>/.test(line)) {
        if (para.length || list || table) flush();
        (quote = quote || []).push(line.replace(/^\s*>\s?/, ''));
      } else if (item) {
        if (para.length || table || quote) flush();
        const tag = /\d/.test(item[1]) ? 'ol' : 'ul';
        if (list && list.tag !== tag) flush();
        list = list || { tag, items: [] };
        list.items.push(item[2]);
      } else if (list && /^\s{2,}\S/.test(line)) list.items[list.items.length - 1] += ' ' + line.trim();
      else if (!line.trim() || /^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) flush();
      else { if (list || table || quote) flush(); para.push(line.trim()); }
    }
    flush();
    return blocks.join('');
  }
  function docTable(rows, base) {
    const cells = (row) => row.trim().replace(/^\|/, '').replace(/\|$/, '').split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, '|'));
    const [head, ...body] = rows.filter((row) => !/^\s*\|?\s*:?-{2,}/.test(row)).map(cells);
    return `<div class="table-wrap"><table class="grid doc-table"><thead><tr>${head.map((c) => `<th>${docInline(c, base)}</th>`).join('')}</tr></thead>`
      + `<tbody>${body.map((r) => `<tr>${r.map((c) => `<td>${docInline(c, base)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  }
  /** A doc's `##` and `###` headings, outside its code, for the page's own contents. */
  const docHeadings = (text) => String(text || '').replace(/^```[\s\S]*?^```/gm, '').split('\n')
    .map((line) => /^(#{2,3})\s+(.*)$/.exec(line)).filter(Boolean)
    .map((m) => ({ level: m[1].length, text: m[2], id: 'doc-' + docSlug(m[2]) }));
  Object.assign(Arch, { doc, docHeadings });

  // MARK: - Routes

  /** `#/<folder>`, `#/<file>[:line|:declaration]`, `#/file/<doc>.md`, `#/explorer`, `#/trail/<id>/<n>[;n=<k>]`,
   *  `#/find/<text>`; the project's root when empty. */
  Arch.parseRoute = (hash) => {
    let h = String(hash || '').replace(/^#\/?/, '');
    let q = {};
    const qi = h.indexOf('?');
    if (qi >= 0 && !/^find\//.test(h)) { q = Object.fromEntries(new URLSearchParams(h.slice(qi + 1))); h = h.slice(0, qi); }
    if (/^find(\/|$)/.test(h)) {
      const rest = h.replace(/^find\/?/, '');
      let text = rest;
      try { text = decodeURIComponent(rest); } catch (e) { /* keep it as written */ }
      return { view: 'find', parts: [], rest: text, query: q };
    }
    const parts = h.split('/').filter(Boolean).map((p) => { try { return decodeURIComponent(p); } catch (e) { return p; } });
    if (parts[0] && VIEWS.has(parts[0])) {
      const view = parts.shift();
      return { view, parts, rest: parts.join('/'), query: q };
    }
    if (parts[0] === '.') parts.shift();
    const joined = parts.join('/');
    const at = joined.search(/:[^/]*$/), path = at > 0 ? joined.slice(0, at) : joined, target = at > 0 ? joined.slice(at + 1) : null;
    if (path && idx.files && idx.files.has(path)) return { view: 'path', kind: 'file', path, target, parts, query: q };
    return { view: 'path', kind: 'folder', path: joined.replace(/\/+$/, '') || '.', parts, query: q };
  };
  /** The Explorer's routes: a file of code, the Explorer itself, a trail, a search. */
  Arch.isExplorerRoute = (r) => !!r && ((r.view === 'path' && r.kind === 'file') || r.view === 'explorer' || r.view === 'trail' || r.view === 'find');
  Arch.go = (hash) => { if (location.hash !== hash) location.hash = hash; else Arch.render(); };

  // MARK: - Feedback

  let toastTimer = null;
  Arch.toast = (text) => {
    const el = document.getElementById('toast');
    el.textContent = text;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 1800);
  };
  Arch.copy = (text) => {
    const done = () => Arch.toast('Copied ' + fmt.clip(text, 60));
    const fallback = () => {
      const area = document.createElement('textarea');
      area.value = text; area.setAttribute('readonly', ''); area.style.position = 'fixed'; area.style.opacity = '0';
      document.body.appendChild(area); area.select();
      try { document.execCommand('copy'); done(); } catch (e) { Arch.toast('Select and copy: ' + text); }
      area.remove();
    };
    try { navigator.clipboard.writeText(text).then(done, fallback); } catch (e) { fallback(); }
  };
  Arch.tip = {
    show(content, x, y) {
      const el = document.getElementById('tooltip');
      el.innerHTML = String(content);
      el.hidden = false;
      const r = el.getBoundingClientRect();
      el.style.left = Math.max(8, Math.min(window.innerWidth - r.width - 8, x + 14)) + 'px';
      el.style.top = Math.max(8, y + r.height + 24 > window.innerHeight ? y - r.height - 12 : y + 16) + 'px';
    },
    hide() { const el = document.getElementById('tooltip'); if (el) el.hidden = true; },
  };

  /** A small SVG icon by name, drawn with the current colour. */
  Arch.icon = (name) => {
    const paths = {
      explorer: '<path d="M5.5 4 2 8l3.5 4M10.5 4 14 8l-3.5 4"/>',
      trail: '<path d="M3.5 8a4.5 4.5 0 0 1 8.2-2.6"/><path d="M12.5 8a4.5 4.5 0 0 1-8.2 2.6"/><path d="M11.7 2.6v2.8H8.9M4.3 13.4v-2.8h2.8"/>',
      folder: '<path d="M2 4.5h4l1.5 1.5H14v7H2Z"/>',
      root: '<path d="M8 2 14 5 8 8 2 5Z"/><path d="M2 8l6 3 6-3M2 11l6 3 6-3"/>',
      doc: '<path d="M3 2.5h7.5a2 2 0 0 1 2 2V14H5a2 2 0 0 1-2-2Z"/><path d="M3 12a2 2 0 0 1 2-2h7.5"/>',
    };
    return raw(`<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${paths[name] || ''}</svg>`);
  };
  /** A folder's mark on the rail: the first letters of its name. */
  Arch.mark = (part) => raw(`<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><rect x="0.7" y="2.2" width="14.6" height="11.6" rx="3" fill="none" stroke="currentColor" stroke-width="1.1"/><text x="8" y="10.9" text-anchor="middle" font-size="7.2" font-weight="600" font-family="ui-monospace, SF Mono, Menlo, monospace" fill="currentColor">${esc(String(part).replace(/[^A-Za-z0-9]/g, '').slice(0, 2))}</text></svg>`);

  // MARK: - DOM, for the views that keep their own elements across renders (the Explorer, the ask orb)

  /** An element with attributes and children. Text is always a text node; nothing here parses HTML. */
  Arch.h = function h(tag, attrs, children) {
    const node = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => {
      if (v == null || v === false) return;
      if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v === true ? '' : String(v));
    });
    const add = (c) => {
      if (c == null || c === false) return;
      if (Array.isArray(c)) { c.forEach(add); return; }
      node.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
    };
    add(children);
    return node;
  };

  /** One line of code as tokens, `[class, text]`: keywords, types, strings, numbers and comments. A lexer per line, not a
   *  parser; Swift's words, which most C-family code shares. */
  const WORDS = /^(func|let|var|const|if|else|guard|return|for|in|of|while|struct|enum|class|actor|interface|type|def|fn|public|package|private|fileprivate|internal|protected|static|mutating|nonisolated|case|switch|default|nil|null|undefined|None|true|false|True|False|self|Self|this|init|deinit|extension|protocol|import|export|from|throws|throw|try|where|some|any|inout|defer|break|continue|repeat|do|catch|lazy|weak|final|override|async|await|typealias|associatedtype|subscript|get|set|is|as|new|function|lambda|yield|impl|trait|mod|use|pub|match)$/;
  Arch.tokens = function tokens(line) {
    const parts = [], re = /(\/\/.*$|#(?![!\w(]).*$)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(\b\d[\d_]*(?:\.\d+)?(?:e-?\d+)?\b|\b0x[0-9A-Fa-f_]+\b)|(@?[A-Za-z_][A-Za-z0-9_]*)|(\s+)|([^\sA-Za-z0-9_"'@/#]+|\/|#)/g;
    let m;
    while ((m = re.exec(line))) {
      parts.push([m[1] ? 'tk-c' : m[2] ? 'tk-s' : m[3] ? 'tk-n' : m[4] ? (WORDS.test(m[4]) ? 'tk-k' : /^@?[A-Z]/.test(m[4]) ? 'tk-t' : '') : '', m[0]]);
      if (m[0] === '') re.lastIndex++;
    }
    return parts;
  };
  Arch.highlight = (line) => Arch.tokens(line).map(([cls, text]) => (cls ? Arch.h('span', { class: cls }, text) : document.createTextNode(text)));
  Arch.highlightHTML = (line) => Arch.tokens(line).map(([cls, text]) => (cls ? `<span class="${cls}">${esc(text)}</span>` : esc(text))).join('');

  if (D) buildIndexes();
})();
