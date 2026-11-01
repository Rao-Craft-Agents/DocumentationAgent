/* The documentation site — the ask orb: on every view, an orb at the bottom right that opens into a mini chat about
   what the reader is looking at. On the Explorer it reads the selected declaration, its code and its place on the
   trails; on any other view it reads the view's text. On every view it can read the rest of the codebase through
   four tools the page runs from its own data, loaded on the first question. Generalized from Craft's companion.
   PIN: the one network call the site makes, and only when the reader sends a message: a chat completions API (Mistral's
   by default, or any compatible endpoint), from the browser, with a key the person writes into local/ask.js beside
   this page, which the site's .gitignore keeps out of the repository, or one the reader pastes, which stays in this
   browser. The documentation never writes a key. Replies are rendered as text and a few marks of markdown, never as
   HTML. Arch.ask.transport can be replaced, so the checks never call the network. */
(() => {
  'use strict';
  const Arch = window.Arch;
  const h = Arch.h;
  if (!Arch.data) return;
  const TITLE = Arch.data.meta.title;
  const ENDPOINTS = { mistral: 'https://api.mistral.ai/v1/chat/completions', openai: 'https://api.openai.com/v1/chat/completions' };
  const DEFAULTS = { provider: 'mistral', model: 'mistral-large-latest' };
  const HISTORY = 12;
  const ROUNDS = 8; // reads before the model must answer; a read asked for past it is not run
  const READING = [
    'You can read the whole codebase. The map below opens with the trails, walks through the code in the order it runs, then the Granite services lowest rank first with their events and the reducer each names, then the components, then every file of code with what it is, and your tools read any declaration, file or line of text.',
    'Start from what the reader is looking at. For how the project does anything, start from the service and the reducer that do it. When a question reaches past what you were given, read the declarations you need before you answer, and name what you read. ' +
    'Read rather than guess, and stop reading once you can answer.',
  ].join('\n');
  const SYSTEM = [
    'You are the guide on the documentation site of ' + TITLE + ', written from its code.',
    (Arch.data.meta.tagline ? TITLE + ': ' + Arch.data.meta.tagline + ' ' : '') + 'The site lists its folders, its files with their declarations, its call graph and its Granite flows.',
    'Answer the reader\'s question about what they are looking at, described below.',
    '- Give the answer first, in plain words and short sentences. Most answers fit in a few sentences.',
    '- Ground every claim about the project in what follows. When it does not say, say so instead of guessing.',
    '- Never invent numbers, results, file names or line numbers.',
    '- Point at code as File.swift:line, with the line numbers given.',
    '- Use `backticks` for identifiers, and a fenced block only to show code.',
  ].join('\n');
  const PASTED = 'a key pasted in this browser';

  const state = { messages: [], busy: null, tried: false, loading: false, pasted: '', config: null };
  const ui = {};

  // MARK: - What the reader is looking at

  function context() {
    const x = Arch.explorer && Arch.explorer.context ? Arch.explorer.context() : null;
    if (x) return x;
    const route = Arch.route || {};
    const view = route.view === 'path' ? 'folder ' + (route.path === '.' ? TITLE : route.path) : route.view === 'file' ? 'doc ' + route.rest : (Arch.views[route.view] || {}).title || 'this page';
    const parts = [document.getElementById('main'), document.getElementById('inspector')].filter(Boolean)
      .map((el) => (el.innerText || el.textContent || '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()).filter(Boolean);
    let text = parts.join('\n\nIn the inspector beside it:\n\n');
    if (text.length > 9000) text = text.slice(0, 9000) + '\n[the view goes on]';
    return { kind: 'page', label: view, text: 'The reader is on the site\'s ' + view + ' view (' + location.hash + '). What it shows:\n\n' + text };
  }
  const starters = (kind) => (kind === 'code' ? ['What does this do?', 'Why is it built this way?', 'What calls it, and when?']
                                              : ['Explain this view in two sentences.', 'What should I understand first here?']);

  // MARK: - The key

  let waiting = [];
  /** Calls done with the key and model: this Mac's (local/ask.js, loaded once, on first use), else a pasted key, else null. */
  function withConfig(done) {
    const local = window.DOCS_ASK;
    if (local && local.key) return done(Object.assign({}, DEFAULTS, local));
    if (state.loading) { waiting.push(done); return; }
    if (!state.tried) {
      state.tried = true;
      state.loading = true;
      waiting.push(done);
      const s = document.createElement('script');
      const settle = () => { state.loading = false; const all = waiting; waiting = []; all.forEach(withConfig); };
      s.src = 'local/ask.js';
      s.onload = settle;
      s.onerror = () => { s.remove(); settle(); };
      document.head.appendChild(s);
      return;
    }
    const key = state.pasted || Arch.store.get('ask.key', '');
    done(key ? Object.assign({}, DEFAULTS, { key, source: PASTED }) : null);
  }

  // MARK: - Talking to the provider

  /** Where a config sends: its own endpoint, else its provider's. */
  const endpointOf = (config) => config.endpoint || ENDPOINTS[config.provider] || ENDPOINTS.mistral;

  /** Sends one request, calls onDelta with each piece of text as it streams, and resolves to { content, toolCalls }. Replaceable for tests. */
  function chat(body, key, onDelta, signal, config) {
    let content = '';
    const calls = [];
    return fetch(endpointOf(config || state.config || DEFAULTS), {
      method: 'POST', signal,
      headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream', Authorization: 'Bearer ' + key },
      body: JSON.stringify(body),
    }).then((res) => {
      if (!res.ok) return res.text().then((t) => { const e = new Error(t.slice(0, 300)); e.status = res.status; throw e; });
      const reader = res.body.getReader(), decoder = new TextDecoder();
      let buffer = '';
      const pump = () => reader.read().then((r) => {
        if (r.done) return { content, toolCalls: calls.filter((c) => c && c.function && c.function.name) };
        buffer += decoder.decode(r.value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop();
        lines.forEach((line) => {
          line = line.trim();
          if (line.indexOf('data:') !== 0) return;
          const data = line.slice(5).trim();
          if (!data || data === '[DONE]') return;
          try {
            const delta = ((JSON.parse(data).choices || [])[0] || {}).delta || {};
            let c = delta.content;
            if (Array.isArray(c)) c = c.filter((p) => p && p.type === 'text').map((p) => p.text).join('');
            if (c) { content += c; onDelta(c); }
            (delta.tool_calls || []).forEach((tc) => {
              const known = tc.id ? calls.findIndex((x) => x.id === tc.id) : -1;
              const at = typeof tc.index === 'number' ? tc.index : known >= 0 ? known : tc.id ? calls.length : Math.max(0, calls.length - 1);
              const call = calls[at] || (calls[at] = { id: '', type: 'function', function: { name: '', arguments: '' } });
              if (tc.id) call.id = tc.id;
              if (tc.function) {
                if (tc.function.name) call.function.name = tc.function.name;
                if (tc.function.arguments) call.function.arguments += typeof tc.function.arguments === 'string' ? tc.function.arguments : JSON.stringify(tc.function.arguments);
              }
            });
          } catch (e) { /* a partial line: the next read completes it */ }
        });
        return pump();
      });
      return pump();
    });
  }

  /** True when the Explorer's sources are loaded, so the model may read the rest of the codebase. */
  const canRead = () => !!(Arch.explorer && Arch.explorer.model && Arch.explorer.model());
  /** The first request for a question: the house rules; once the sources are loaded, on any view, the codebase map
   *  and the tools that read it; then what the reader is looking at, the selected code on the Explorer or the view's
   *  text elsewhere. */
  function request(config, ctx) {
    const code = canRead();
    const about = ctx.kind === 'code' ? 'What the reader has selected:' : 'What the reader is looking at:';
    const system = (code ? SYSTEM + '\n' + READING + '\n\nThe codebase at a glance:\n\n' + Arch.explorer.map() : SYSTEM) + '\n\n' + about + '\n\n' + ctx.text;
    const body = {
      model: config.model, stream: true, temperature: 0.3, max_tokens: 900,
      messages: [{ role: 'system', content: system }].concat(
        state.messages.filter((m) => m.role === 'user' || (m.role === 'assistant' && m.text)).slice(-HISTORY).map((m) => ({ role: m.role, content: m.text }))),
    };
    if (code) { body.tools = Arch.explorer.tools; body.tool_choice = 'auto'; }
    if (config.reasoning) body.reasoning_effort = config.reasoning;
    return body;
  }

  function send(text) {
    text = (text || '').trim();
    if (!text || state.busy) return;
    withConfig((config) => {
      if (!config) { renderLog(); return; }
      const ctx = context();
      state.messages.push({ role: 'user', text, about: ctx.label });
      const reply = { role: 'assistant', text: '', draft: '', reads: [], pending: true };
      state.messages.push(reply);
      ui.input.value = '';
      fitInput();
      const controller = new AbortController();
      state.busy = controller;
      renderLog();
      let queued = false;
      const paint = () => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; paintLast(); }); } };
      const onDelta = (piece) => { reply.draft += piece; reply.pending = false; paint(); };
      // The sources load once, on the first question from any view; until they have, the orb reads the view alone.
      const ready = Arch.explorer && Arch.explorer.ensure ? Arch.explorer.ensure().catch(() => false) : Promise.resolve(false);
      let body = null, rounds = 0;
      // A round that asks to read runs those reads here, from the code this page holds, and asks again; its own words are dropped.
      // PIN: the cap is the page's, not the model's. `tool_choice: 'none'` is a request a model can ignore, and one that
      // kept asking to read looped; past ROUNDS a read is not run, and the round's words are the answer.
      const round = () => Arch.ask.transport(body, config.key, onDelta, controller.signal, config).then((got) => {
        const calls = (got && got.toolCalls) || [];
        if (!calls.length || !body.tools || rounds >= ROUNDS) {
          reply.text += reply.draft;
          reply.draft = '';
          if (calls.length && !reply.text) reply.note = 'Stopped after ' + ROUNDS + ' rounds of reading without an answer. Ask again, more narrowly.';
          return undefined;
        }
        reply.draft = '';
        rounds++;
        body.messages.push({ role: 'assistant', content: (got && got.content) || '', tool_calls: calls });
        calls.forEach((call) => {
          const out = Arch.explorer.tool(call.function.name, call.function.arguments);
          if (out.read && !reply.reads.some((r) => r.label === out.read.label)) reply.reads.push(out.read);
          body.messages.push({ role: 'tool', name: call.function.name, tool_call_id: call.id, content: out.text });
        });
        reply.pending = true;
        paint();
        if (rounds >= ROUNDS) body.tool_choice = 'none';
        return round();
      });
      ready.then(() => { body = request(config, ctx); return round(); }).then(() => {
        if (!reply.text) reply.error = 'The model sent no answer. Ask again, or rephrase.';
      }, (e) => {
        if (e && e.name === 'AbortError') reply.note = 'Stopped.';
        else if (e && e.status === 401) reply.error = 'The provider refused the key. Put another in local/ask.js, or paste one.';
        else if (e && e.status === 429) reply.error = 'The provider is limiting this key for now. Try again in a moment.';
        else if (e && e.status) reply.error = 'The provider answered ' + e.status + ': ' + e.message;
        else reply.error = 'No answer from the provider. The orb needs the network; the rest of the site does not.';
      }).then(() => {
        reply.pending = false;
        state.busy = null;
        renderLog();
      });
    });
  }

  // MARK: - Showing replies, as text

  /** A citation the model wrote, as a link into the site: File.swift:N, or a path ending so, matched by its suffix
   *  among the loaded files when exactly one fits. Null when it names nothing the site has. */
  function citeLink(text, inner) {
    const m = canRead() ? Arch.explorer.model() : null;
    const r = /^((?:[\w+.\-]+\/)*[\w+\-]+\.[A-Za-z]{1,6}):(\d+)$/.exec(text);
    if (r && m) {
      const hit = m.files.filter((f) => f.path === r[1] || f.path.slice(-r[1].length - 1) === '/' + r[1]);
      if (hit.length === 1) return h('a', { href: Arch.href.file(hit[0].path, r[2]), title: 'Open it in the Explorer' }, inner);
    }
    return null;
  }
  function inline(s) {
    const out = [];
    s.split(/(`[^`\n]+`|\*\*[^*\n]+\*\*|\b(?:[\w+.\-]+\/)*[\w+-]+\.(?:swift|ts|tsx|js|jsx|py|go|rs|kt|java|rb|m|mm|h|c|cpp):\d+\b)/).forEach((t) => {
      if (!t) return;
      // A citation in backticks is still a citation: the code span becomes the link's text.
      if (/^`[^`]+`$/.test(t)) { const code = h('code', null, t.slice(1, -1)); out.push(citeLink(t.slice(1, -1), code) || code); }
      else if (/^\*\*[^*]+\*\*$/.test(t)) out.push(h('b', null, t.slice(2, -2)));
      else out.push(citeLink(t, t) || t);
    });
    return out;
  }
  function markup(text) {
    const frag = document.createDocumentFragment();
    text.split('```').forEach((block, i) => {
      if (i % 2) {
        const pre = h('pre', { class: 'ask-code' });
        block.replace(/^[\w+-]*\n/, '').replace(/\n$/, '').split('\n').forEach((line, k) => {
          if (k) pre.appendChild(document.createTextNode('\n'));
          pre.appendChild(h('span', null, Arch.highlight(line)));
        });
        frag.appendChild(pre);
        return;
      }
      block.split(/\n{2,}/).forEach((para) => {
        para = para.replace(/^\n+|\n+$/g, '');
        if (!para.trim()) return;
        const lines = para.split('\n');
        if (lines.every((l) => /^\s*([-*•]|\d+[.)])\s+/.test(l))) {
          const list = h(/^\s*\d/.test(lines[0]) ? 'ol' : 'ul');
          lines.forEach((l) => list.appendChild(h('li', null, inline(l.replace(/^\s*([-*•]|\d+[.)])\s+/, '')))));
          frag.appendChild(list);
        } else if (/^#{1,4}\s/.test(lines[0]) && lines.length === 1) {
          frag.appendChild(h('p', null, h('b', null, inline(lines[0].replace(/^#+\s*/, '')))));
        } else {
          const p = h('p');
          lines.forEach((l, k) => { if (k) p.appendChild(h('br')); p.appendChild(h('span', null, inline(l))); });
          frag.appendChild(p);
        }
      });
    });
    return frag;
  }
  function bubble(m) {
    if (m.role === 'user') return h('div', { class: 'ask-msg user' }, m.text);
    const div = h('div', { class: 'ask-msg bot' + (m.error ? ' error' : '') });
    if (m.reads && m.reads.length) {
      div.appendChild(h('p', { class: 'ask-reads' }, ['Read ', m.reads.map((r, i) => [i ? ' · ' : '', r.href ? h('a', { href: r.href, title: 'Open it in the Explorer' }, r.label) : h('span', null, r.label)])]));
    }
    const shown = (m.text || '') + (m.draft || '');
    if (m.pending && !shown) div.appendChild(h('span', { class: 'ask-wait' }, m.reads && m.reads.length ? 'Reading more…' : 'Reading…'));
    if (shown) div.appendChild(markup(shown));
    if (m.error) div.appendChild(h('p', null, m.error));
    if (m.note) div.appendChild(h('p', { class: 'ask-aside' }, m.note));
    return div;
  }
  function paintLast() {
    const last = ui.log.lastElementChild, m = state.messages[state.messages.length - 1];
    if (!last || !m) return;
    last.replaceWith(bubble(m));
    ui.log.scrollTop = ui.log.scrollHeight;
  }
  function renderLog(after) {
    ui.log.textContent = '';
    withConfig((config) => {
      state.config = config;
      ui.log.textContent = '';
      if (!config) { ui.log.appendChild(setup()); syncControls(); if (after) after(); return; }
      const ctx = context();
      let lastAbout = null;
      if (!state.messages.length) {
        ui.log.appendChild(h('p', { class: 'ask-msg note' }, ctx.kind === 'code'
          ? 'Ask about the code you have selected. The chat starts there, and reads the rest of the codebase when a question reaches past it.'
          : 'Ask about this view. The answer starts from what the view shows, and reads the code itself when a question reaches past it.'));
        ui.log.appendChild(h('div', { class: 'ask-starters' }, starters(ctx.kind).map((q) => {
          const b = h('button', { type: 'button' }, q);
          b.addEventListener('click', () => send(q));
          return b;
        })));
      }
      state.messages.forEach((m) => {
        if (m.role === 'user' && m.about !== lastAbout) { ui.log.appendChild(h('p', { class: 'ask-msg note' }, 'About ' + m.about)); lastAbout = m.about; }
        ui.log.appendChild(bubble(m));
      });
      ui.foot.textContent = '';
      ui.foot.appendChild(document.createTextNode(config.model + ' via ' + (config.provider || 'mistral') + ', with ' + (config.source || 'a key') + '. It reads what you see here, and it can be wrong.'));
      if (config.source === PASTED) {
        const forget = h('button', { type: 'button', class: 'ask-link' }, 'Forget the key');
        forget.addEventListener('click', () => { state.pasted = ''; Arch.store.remove('ask.key'); renderLog(); });
        ui.foot.appendChild(document.createTextNode(' '));
        ui.foot.appendChild(forget);
      }
      ui.log.scrollTop = ui.log.scrollHeight;
      syncControls();
      if (after) after();
    });
  }
  function setup() {
    const field = h('input', { type: 'password', autocomplete: 'off', spellcheck: 'false', placeholder: 'Mistral API key', 'aria-label': 'API key' });
    const use = h('button', { type: 'button' }, 'Use this key');
    const take = () => {
      const key = field.value.trim();
      if (!key) return;
      state.pasted = key;
      Arch.store.set('ask.key', key);
      renderLog();
      ui.input.focus();
    };
    use.addEventListener('click', take);
    field.addEventListener('keydown', (e) => { if (e.key === 'Enter') { take(); e.preventDefault(); } });
    ui.foot.textContent = '';
    return h('div', { class: 'ask-setup' }, [
      h('p', null, 'The orb needs a key. Write one into local/ask.js beside this page: window.DOCS_ASK = { provider: "mistral", model: "mistral-large-latest", key: "…" }, or an OpenAI-compatible endpoint and model. Or paste a Mistral key here: a pasted key stays in this browser. The site\u2019s .gitignore keeps local/ out of the repository.'),
      h('div', { class: 'ask-keyrow' }, [field, use]),
    ]);
  }
  /** Forgets the conversation, stopping an answer in progress. Each question reads the view afresh, so nothing else carries over. */
  function newChat() {
    if (state.busy && state.busy.abort) state.busy.abort();
    state.messages = [];
    renderLog(() => { if (!ui.input.disabled) ui.input.focus(); });
  }
  function syncControls() {
    const busy = !!state.busy, ready = !!state.config;
    ui.reset.disabled = !state.messages.length;
    ui.send.textContent = busy ? 'Stop' : 'Send';
    ui.send.setAttribute('aria-label', busy ? 'Stop the answer' : 'Send');
    ui.input.disabled = !ready;
    ui.send.disabled = !ready;
  }

  // MARK: - The orb and the panel

  function updateAbout() {
    if (!ui.about) return;
    const ctx = context();
    ui.about.textContent = 'About ' + (ctx.kind === 'code' ? ctx.label : 'this view: ' + ctx.label);
    ui.input.placeholder = ctx.kind === 'code' ? 'Ask about this code' : 'Ask about this view';
  }
  function fitInput() { ui.input.style.height = 'auto'; ui.input.style.height = Math.min(ui.input.scrollHeight + 2, 128) + 'px'; }
  function open() {
    ui.panel.hidden = false;
    ui.orb.hidden = true;
    ui.orb.setAttribute('aria-expanded', 'true');
    updateAbout();
    renderLog(() => (ui.input.disabled ? ui.panel.querySelector('.ask-setup input') || ui.close : ui.input).focus());
  }
  function close() {
    ui.panel.hidden = true;
    ui.orb.hidden = false;
    ui.orb.setAttribute('aria-expanded', 'false');
    ui.orb.focus();
  }
  function mount() {
    if (ui.orb || !document.body) return;
    ui.orb = h('button', { type: 'button', class: 'ask-orb', 'aria-label': 'Ask about what you are reading', title: 'Ask about what you are reading',
                           'aria-expanded': 'false', 'aria-controls': 'ask-panel' });
    ui.about = h('span', { class: 'ask-about' });
    ui.close = h('button', { type: 'button', class: 'ask-close', 'aria-label': 'Close the chat', title: 'Close (Esc)' }, '×');
    ui.reset = h('button', { type: 'button', class: 'ask-new', title: 'Forget this conversation and start again', disabled: true }, 'New chat');
    ui.log = h('div', { class: 'ask-log', 'aria-live': 'polite' });
    ui.input = h('textarea', { rows: 1, 'aria-label': 'Your question', spellcheck: 'true' });
    ui.send = h('button', { type: 'submit' }, 'Send');
    ui.foot = h('p', { class: 'ask-foot' });
    const form = h('form', { class: 'ask-form' }, [ui.input, ui.send]);
    ui.panel = h('section', { class: 'ask', id: 'ask-panel', role: 'dialog', 'aria-label': 'Ask about what you are reading', hidden: true }, [
      h('div', { class: 'ask-head' }, [h('span', { class: 'ask-dot', 'aria-hidden': 'true' }), h('span', { class: 'ask-title' }, [h('b', null, 'Ask'), ui.about]), ui.reset, ui.close]),
      ui.log, form, ui.foot,
    ]);
    ui.orb.addEventListener('click', open);
    ui.close.addEventListener('click', close);
    ui.reset.addEventListener('click', newChat);
    ui.panel.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { close(); e.preventDefault(); }
      if (!((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k')) e.stopPropagation();
    });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      if (state.busy) { state.busy.abort(); return; }
      send(ui.input.value);
    });
    ui.input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); form.requestSubmit(); } });
    ui.input.addEventListener('input', fitInput);
    window.addEventListener('docs:context', updateAbout);
    window.addEventListener('hashchange', () => setTimeout(updateAbout, 0));
    document.body.appendChild(ui.orb);
    document.body.appendChild(ui.panel);
  }

  Arch.ask = {
    transport: chat,
    open: () => { if (ui.orb) open(); }, close: () => { if (ui.orb) close(); }, newChat: () => { if (ui.orb) newChat(); },
    context, request: (ctx) => request(DEFAULTS, ctx || context()), rounds: ROUNDS,
    selfCheck() {
      const ctx = context(), body = request(DEFAULTS, ctx);
      return [
        { name: 'the orb reads what the reader is looking at', ok: !!(ctx && ctx.text && ctx.text.length > 40 && ctx.text.length < 30000), detail: ctx ? ctx.kind + ', ' + ctx.text.length + ' characters' : '' },
        { name: 'a request carries the context and the house rules, and nothing calls the network until a message is sent', ok: body.messages[0].role === 'system' && body.messages[0].content.indexOf(ctx.text.slice(0, 60)) >= 0 && !state.messages.length },
        { name: 'once the sources are loaded, a request from any view carries the codebase map and the tools that read the rest', ok: !canRead() || (body.tools && body.tools.length === 4 && body.messages[0].content.indexOf('The codebase at a glance') >= 0),
          detail: canRead() ? Math.round(body.messages[0].content.length / 1000) + ' thousand characters of system message' : 'the sources are not loaded on this view' },
      ];
    },
  };
  mount();
})();
