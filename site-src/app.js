/* The documentation site — the shell: the rail, routing and rendering, search (⌘K), the theme, the editor settings,
   and the one click handler every view's `data-action` goes through. Generalized from Craft's companion (app.js). */
(() => {
  'use strict';
  const Arch = window.Arch;
  const D = Arch.data;
  const $ = (id) => document.getElementById(id);

  if (!D) {
    $('main').innerHTML = '<h1 class="view-title">No data yet</h1><p class="view-lede">This page reads <code>data.js</code> beside it, which the docs agent writes. Call it again with <code>make: site</code>, then reload.</p>';
    return;
  }
  const { html, fmt, idx } = Arch;
  // The rail follows the project's own folders, named 1:1 after them: the Explorer and its trails, the project's root
  // and each folder at its top, then its docs.
  const viewFor = (r) => (Arch.isExplorerRoute(r) ? 'explorer' : r.view === 'path' ? 'path' : r.view === 'file' ? 'file' : null);

  // MARK: - Theme

  const THEME_KEY = 'docs-site.theme';
  function theme() { try { return localStorage.getItem(THEME_KEY) || 'auto'; } catch (e) { return 'auto'; } }
  function setTheme(value) {
    try { if (value === 'auto') localStorage.removeItem(THEME_KEY); else localStorage.setItem(THEME_KEY, value); } catch (e) { /* convenience only */ }
    if (value === 'auto') delete document.documentElement.dataset.theme; else document.documentElement.dataset.theme = value;
    paintTheme();
  }
  function paintTheme() { const t = theme(); document.querySelectorAll('#theme-switch button').forEach((b) => b.setAttribute('aria-checked', String(b.dataset.value === t))); }

  // MARK: - Chrome

  function chrome() {
    $('brand-name').textContent = D.meta.title;
    $('brand-mark').innerHTML = String(Arch.mark(D.meta.title));
    const el = $('head-chip');
    const c = D.meta.counts || {};
    el.textContent = (D.meta.head ? D.meta.head + ' · ' : '') + fmt.plural(c.files || 0, 'file') + ' of code · ' + fmt.n(c.lines || 0) + ' lines';
    el.title = 'Written by the docs agent' + (D.meta.head ? ' at commit ' + D.meta.head : '') + ' from ' + fmt.plural(c.files || 0, 'file') +
      ((D.meta.skipped || []).length ? '; ' + D.meta.skipped.length + ' left out, listed on the project’s page' : '');
  }
  function rail(route) {
    const spine = D.spine || [];
    const here = route.view === 'path' ? (route.path === '.' ? '.' : route.path.split('/')[0]) : route.view === 'file' ? 'file/' + route.rest.replace(/:\d+$/, '')
      : route.view === 'trail' ? 'trail/' + (route.parts[0] || '') : Arch.isExplorerRoute(route) ? 'explorer' : route.view;
    const item = (id, href, label, icon, hint) => html`<a href="${href}" aria-current="${here === id ? 'page' : 'false'}" title="${hint || label}">${icon}<span class="rail-label">${label}</span></a>`;
    const docs = Object.keys(D.docs || {}).filter((p) => !p.includes('/') || /^docs?\//i.test(p)).slice(0, 14);
    const trails = D.trails || [];
    return html`${item('explorer', Arch.href.explorer(), 'Explorer', Arch.icon('explorer'), 'Every file of code, its declarations, its calls and its flows')}
      ${item('.', '#/', D.meta.title, Arch.icon('root'), D.meta.title + ': the project, how it is built')}
      ${spine.map((name) => item(name, Arch.href.folder(name), name, Arch.mark(name), name + '/'))}
      ${trails.length ? html`<div class="rail-group">Trails</div>${trails.map((t) => item('trail/' + t.id, Arch.href.trail(t.id, 1), t.title, Arch.mark(t.mark), t.say))}` : ''}
      ${docs.length ? html`<div class="rail-group">Docs</div>${docs.map((p) => item('file/' + p, Arch.href.doc(p), D.docs[p].title, Arch.icon('doc'), p))}` : ''}
      <div class="rail-note">Written from the code by the docs agent${D.meta.head ? html` at <code>${D.meta.head}</code>` : ''}. After the code changes, ask for <code>$docs</code> again to bring it level.</div>`;
  }

  // MARK: - Render

  let lastScrollKey = null;
  const scrollKey = (r) => (viewFor(r) === 'path' ? 'path/' + r.path : viewFor(r) === 'file' ? 'file/' + r.rest : viewFor(r));

  Arch.render = function render() {
    const route = (Arch.route = Arch.parseRoute(location.hash));
    const view = Arch.views[viewFor(route)];
    const main = $('main'), inspector = $('inspector');
    $('rail').innerHTML = String(rail(route));
    Arch.tip.hide();
    if (!view) {
      main.innerHTML = String(html`<h1 class="view-title">Nothing at ${location.hash}</h1><p><a href="#/">Start from the top</a></p>`);
      inspector.innerHTML = '';
      return;
    }
    try {
      const page = view.render(route);
      main.innerHTML = String(page.main);
      inspector.innerHTML = String(page.inspector || '');
      inspector.scrollTop = 0;
      const key = scrollKey(route);
      if (key !== lastScrollKey) { main.scrollTop = 0; window.scrollTo(0, 0); }
      lastScrollKey = key;
      if (view.after) view.after(route, main, inspector);
      const name = route.view === 'path' ? (route.path === '.' ? '' : route.path.split('/').pop()) : route.view === 'file' ? (Arch.own(D.docs, route.rest) || {}).title || view.title : view.title;
      document.title = (name ? name + ' · ' : '') + D.meta.title;
    } catch (err) {
      console.error(err);
      main.innerHTML = String(html`<div class="banner bad">This view could not be drawn: ${err.message}.</div><pre class="block">${err.stack || ''}</pre>`);
    }
  };

  // MARK: - Search

  let entries = null, results = [], active = 0;
  function buildSearch() {
    const E = [];
    const add = (kind, label, sub, href, extra, weight) => E.push({ kind, label, sub: sub || '', href, key: (label + ' ' + (extra || '')).toLowerCase(), subKey: String(sub || '').toLowerCase(), weight: weight || 0 });
    Object.entries(D.folders || {}).forEach(([path, f]) => { if (path !== '.') add('Folders', f.name, path + (f.about && f.about.text ? ' · ' + fmt.clip(f.about.text, 70) : ''), Arch.href.folder(path), path, 9); });
    (D.services || []).forEach((s) => add('Services', s.name, s.events.map((e) => e.event).join(', '), Arch.href.file(s.path, s.line), s.what || '', 9));
    (D.components || []).forEach((s) => add('Components', s.name, s.folder, Arch.href.file(s.path, s.line), s.what || '', 8));
    (D.services || []).concat(D.components || []).forEach((s) => s.events.forEach((e) => { if (e.path) add('Events', s.name + '.' + e.event, e.reducer + (e.doc ? ' · ' + fmt.clip(e.doc, 60) : ''), Arch.href.file(e.path, e.line), e.reducer, 7); }));
    (D.trails || []).forEach((t) => add('Trails', t.title, t.subtitle, Arch.href.trail(t.id, 1), 'trail walk', 8));
    Object.entries(D.docs || {}).forEach(([path, d]) => add('Docs', d.title, path, Arch.href.doc(path), d.text.slice(0, 4000), 7));
    Object.entries(D.types || {}).forEach(([name, hits]) => { const h = hits.find((x) => !x.nested) || hits[0]; add('Types', name, `${h.kind} · ${h.path.split('/').pop()}:${h.line}`, Arch.href.file(h.path, h.line), '', 8); });
    D.files.forEach((f) => add('Files', f.path.split('/').pop(), f.path.replace(/\/?[^/]+$/, '') || '.', Arch.href.file(f.path), f.path, 6));
    D.files.forEach((f) => (f.decls || []).forEach(([kind, name, line]) => { if (kind === 'func') add('Functions', name + '()', `${f.path.split('/').pop()}:${line}`, Arch.href.file(f.path, line), '', 0); }));
    return E;
  }
  function score(e, q, words) {
    let s;
    const label = e.label.toLowerCase();
    if (label === q) s = 100;
    else if (label.startsWith(q)) s = 82;
    else if (new RegExp('[\\s./_·(-]' + q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).test(label)) s = 62;
    else if (e.key.includes(q)) s = 46;
    else if (words.length > 1 && words.every((w) => e.key.includes(w) || e.subKey.includes(w))) s = 28;
    else if (e.subKey.includes(q)) s = 16;
    else return 0;
    return s + e.weight - Math.min(8, label.length / 14);
  }
  function mark(label, q) {
    const i = label.toLowerCase().indexOf(q);
    return i < 0 ? html`${label}` : html`${label.slice(0, i)}<b>${label.slice(i, i + q.length)}</b>${label.slice(i + q.length)}`;
  }
  function runSearch() {
    const q = $('search-input').value.trim().toLowerCase();
    const box = $('search-results');
    if (!q) {
      results = [];
      const sample = (D.services || [])[0] || null, file = D.files[0];
      box.innerHTML = String(html`<div class="search-empty">Try a folder, a type${sample ? html`, <b>${sample.name}</b>` : ''}${file ? html`, <b>${file.path.split('/').pop()}</b>` : ''}, or press ↵ to look for the text in the code.</div>`);
      return;
    }
    entries = entries || buildSearch();
    const words = q.split(/\s+/).filter(Boolean);
    results = entries.map((e) => [score(e, q, words), e]).filter(([s]) => s > 0).sort((a, b) => b[0] - a[0]).slice(0, 60).map(([, e]) => e);
    results.push({ kind: 'In the code', label: 'Find “' + $('search-input').value.trim() + '” in the Explorer', sub: 'declarations, signatures and text', href: Arch.href.find($('search-input').value.trim()) });
    active = 0;
    const groups = [];
    results.forEach((e) => { let g = groups.find((x) => x.kind === e.kind); if (!g) { g = { kind: e.kind, items: [] }; groups.push(g); } g.items.push(e); });
    results = groups.flatMap((g) => g.items);
    let n = 0;
    box.innerHTML = String(html`${groups.map((g) => html`<div class="search-group">${g.kind}</div>${g.items.map((e) => { const i = n++; return html`<a class="search-item" role="option" href="${e.href}" data-i="${i}" aria-selected="${i === 0}"><span class="l">${mark(e.label, q)}</span><span class="s">${e.sub}</span></a>`; })}`)}`);
  }
  function moveActive(d) {
    if (!results.length) return;
    active = (active + d + results.length) % results.length;
    document.querySelectorAll('.search-item').forEach((el) => el.setAttribute('aria-selected', String(+el.dataset.i === active)));
    const el = document.querySelector(`.search-item[data-i="${active}"]`);
    if (el) el.scrollIntoView({ block: 'nearest' });
  }
  function openSearch() { $('search').hidden = false; const input = $('search-input'); input.focus(); input.select(); runSearch(); }
  function closeSearch() { $('search').hidden = true; }

  // MARK: - Settings

  function openSettings(show) {
    const pop = $('settings'), button = $('settings-button');
    const shown = show == null ? pop.hidden : show;
    pop.hidden = !shown;
    button.setAttribute('aria-expanded', String(shown));
    if (shown) {
      $('setting-scheme').value = Arch.settings.scheme;
      $('setting-root').value = Arch.settings.root || '';
      $('setting-root-hint').textContent = Arch.settings.pageRoot
        ? `This page belongs to ${Arch.settings.pageRoot}. Links open files in the editor at their line.`
        : 'This page cannot tell where the project is. Enter its folder to make code links open in the editor.';
    }
  }

  // MARK: - Events

  const handlers = {
    'search-open': openSearch,
    theme: (el) => setTheme(el.dataset.value),
    'settings-toggle': () => openSettings(),
    'settings-save': () => {
      Arch.settings.scheme = $('setting-scheme').value;
      Arch.settings.root = $('setting-root').value.trim().replace(/\/$/, '') || Arch.settings.pageRoot;
      Arch.store.set('settings', { scheme: Arch.settings.scheme, root: Arch.settings.root === Arch.settings.pageRoot ? null : Arch.settings.root });
      openSettings(false);
      Arch.toast('Editor links updated');
      Arch.render();
    },
    'settings-reset': () => { $('setting-root').value = Arch.settings.pageRoot || ''; },
    copy: (el) => Arch.copy(el.dataset.text),
    'scroll-to': (el) => { const target = document.getElementById(el.dataset.target); if (target) target.scrollIntoView({ block: 'start' }); },
  };

  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-action]');
    if (el) {
      const fn = handlers[el.dataset.action];
      if (fn) { e.preventDefault(); fn(el, e); return; }
    }
    const row = e.target.closest('tr[data-href]');
    if (row && !e.target.closest('a, button, input, select, summary')) { Arch.go(row.dataset.href); return; }
    if (!$('settings').hidden && !e.target.closest('#settings, #settings-button')) openSettings(false);
    if (!$('search').hidden && e.target === $('search')) closeSearch();
    if (e.target.closest('.search-item')) closeSearch();
  });
  document.addEventListener('keydown', (e) => {
    const typing = e.target.matches('input, textarea, select') || e.target.isContentEditable;
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); $('search').hidden ? openSearch() : closeSearch(); return; }
    if (!$('search').hidden) {
      if (e.key === 'Escape') { closeSearch(); return; }
      if (e.key === 'ArrowDown') { e.preventDefault(); moveActive(1); return; }
      if (e.key === 'ArrowUp') { e.preventDefault(); moveActive(-1); return; }
      if (e.key === 'Enter' && results[active]) { e.preventDefault(); closeSearch(); Arch.go(results[active].href); return; }
      return;
    }
    if (e.key === 'Escape') { openSettings(false); return; }
    if (typing) return;
    if (e.key === '/') { e.preventDefault(); openSearch(); }
  });
  $('search-input').addEventListener('input', runSearch);
  $('search-results').addEventListener('mousemove', (e) => {
    const item = e.target.closest('.search-item');
    if (item && +item.dataset.i !== active) { active = +item.dataset.i; moveActive(0); }
  });
  window.addEventListener('hashchange', Arch.render);

  // MARK: - Boot

  chrome();
  paintTheme();
  if (idx.files && !location.hash) history.replaceState(null, '', '#/');
  Arch.render();
})();
