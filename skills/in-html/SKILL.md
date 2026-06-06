---
name: in-html
description: >-
  Create a single self-contained HTML artifact in one of two modes — (1) viz: a
  read-only visualization of an implementation plan, design, or decision (code
  excerpts, mockups, diagrams, tradeoffs); (2) feedback: an interactive panel
  served by a local server that returns structured JSON to the agent in the same
  turn (plannotator-style — ask a focused question with rich context, or run a
  full HITL data-shaping UI with drag-drop / chips / sliders / inline
  annotations; user clicks Submit, server prints the answer to stdout, agent
  continues without the user typing). Use when the user asks for an HTML plan, an
  HTML visualization, an HITL data-shaping UI, a per-turn question / feedback
  panel, "design the ideal interface for this problem", or invokes /in-html.
  Output is one .html file saved to /tmp/in-html/, Pico CSS via CDN, opened in
  the browser.
---

# in-html

Two modes:

- **Mode 1 — viz** (read-only): maximum context in a glanceable form. You're *showing* something.
- **Mode 2 — feedback** (interactive, server-backed): get structured JSON back from the user in the same turn. You need something *from* them.

Pick by direction. If the artifact only flows agent → user, it's Mode 1. If anything flows user → agent — one focused answer, an ordered list, a decision tree, a tagged config — it's Mode 2.

## Quick start

1. **Read-only?** Mode 1: **bootstrap from `templates/viz-scaffold.html`** — `cp` it to `/tmp/in-html/<topic>.html`, then fill the slots and delete the example blocks you don't need. Don't hand-write the `<head>`/Pico/dark-toggle/CSS — copying keeps it fast and token-light. Open it (the `xdg-open … || open …` snippet below covers Linux + macOS), print the path. Done.
2. **Need data back?** Mode 2: write the `.html` (start from `templates/feedback-turn.html`), run `feedback-server.ts` as a **foreground** Bash call (it auto-opens a browser tab; user submits; the tab stays with a "Sent" panel for them to close), parse the JSON from stdout, continue the turn.

## Mode 1 — Plan / visualization (read-only)

For: implementation plans, design walkthroughs, architecture explanations, before/after comparisons, decision logs, RFC-style artifacts.

Include whatever gives maximum context — be generous:

- **Code excerpts** in `<pre><code>` blocks. Quote real lines from the repo with `file:line` captions. Add diff-style ± gutters for proposed changes.
- **Mockups** — inline SVG, or HTML/CSS rendering an actual mock of the component/layout.
- **Diagrams** — inline SVG. Use mermaid (`<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>`) only if the diagram benefits from it.
- **Decision tables** — `<table>` of options × tradeoffs, with a recommended row highlighted.
- **File / route trees** as nested lists or `<details>` blocks.
- **Side-by-side panels** for before/after, current/proposed, two competing designs.
- **Annotations** — callout boxes ("why this", "risk", "open question"), inline asides.

Use `<details>` liberally so the user can drill into long code blocks without scrolling past them. Anchor sections with `id="..."` so you can link sections from the chat.

After writing, auto-open and print the path:

```bash
xdg-open /abs/path/to/file.html 2>/dev/null || open /abs/path/to/file.html 2>/dev/null || true
```

## Mode 2 — Interactive feedback (server-backed, plannotator-style)

For: any time you need structured data back from the user in the **same turn**. Use cases span a spectrum:

- **Focused question** — "Customer or User?", a glossary disambiguation, an A/B/C decision. Recommended answer pre-filled, chips for one-click submit, talk-more escape hatch.
- **HITL data shaping** — a decision tree, a chat-routing config, a taxonomy, an ordered priority list, a tagged content schema. Custom controls match the data: drag-drop, sliders, chips, nested blocks.

Both flow through the same mechanism: a local server serves your HTML; the user clicks Submit; the server writes the JSON body to disk, prints it to stdout, and exits. The agent's foreground Bash call returns with the answer.

### How it works

```
agent turn N  ┌─ writes /tmp/in-html/<turn-id>.html (custom UI + max context)
              ├─ runs feedback-server.ts FOREGROUND (with --open)
              │      ├─ server opens browser to http://localhost:<port>/
              │      └─ blocks waiting for POST /submit
              │  user interacts (1-click chip, or 30-step data entry)
              │  user clicks Submit → server writes answer file + prints JSON to stdout + exits 0
              ├─ Bash call returns; agent reads the JSON from stdout
              └─ continues the same turn — no user typing required
```

Plannotator's UX. The one constraint: Claude Code's `Bash` tool caps at 10 minutes (`timeout: 600000`). Plannotator gets 96 hours because it's a real `PermissionRequest` hook. For most question / data-shaping turns 10 minutes is plenty; for longer waits write a real hook — see "Escape hatch".

### Bundled pieces

- `feedback-server.ts` — bun script. `GET /` serves the HTML; `POST /submit` writes the body to `--answer`, prints the JSON to stdout, exits 0. **Opens the browser by default** via `xdg-open` (Linux) / `open` (macOS) / `start` (Windows) — regular tab. After submit the tab stays open showing a "✓ Sent — return to chat" panel; the user closes the tab themselves. Pass `--no-open` to skip opening. Status banners go to stderr. Watchdog timeout (`--timeout`, default 540s — under the Bash 10-min cap). Random port unless `--port` is given. The server **injects a self-contained countdown widget** (fixed top-left) into whatever HTML it serves, so every Mode 2 page shows time-left tied to `--timeout` — turns urgent under 60s, "time up" at 0. No template work needed; it works for `feedback-turn.html` and hand-written artifacts alike.
- `templates/feedback-turn.html` — boilerplate for question-shaped UIs (chips, recommended-answer textarea, talk-more drawer, inline annotations). For richer data-shaping, copy this template's submit/stdout pattern but design your own controls from scratch.

### Design the JSON shape first

Write it as a comment at the top of the HTML. Then design the UI as the inverse of that shape. Whatever your `submit()` POSTs is exactly what the agent will see on stdout — make sure your skill can parse and act on it.

Two recurring shapes:

```js
/*
 * QUESTION (the feedback-turn.html convention):
 * {
 *   turnId, action: "submit" | "talk_more",
 *   answer?,                           // when action=submit
 *   feedback?,                         // user discussion / extra context
 *   annotations?: [{ anchorId, quote, comment }],
 *   timestamp
 * }
 *
 * DATA-SHAPING (custom per artifact):
 * {
 *   turnId,
 *   data: { /* whatever structured shape this task needs *\/ },
 *   timestamp
 * }
 */
```

Both POST to `/submit`. The agent parses the same way — the shape inside is whatever you designed.

### Affordances (mix & match per artifact)

**Question-shaped UIs:**
- **Recommended answer pre-filled** — `<textarea autofocus>{{best guess}}</textarea>`. 1-click accept.
- **Quick-pick chips** — closed-ended pick. `<button data-pick="...">` pre-fills *and* submits.
- **Talk more drawer** — toggle a hidden textarea + send as `{ action: "talk_more" }`.
- **Inline annotations** — `data-annotatable` regions let the user highlight + comment.

**Data-shaping UIs** (design the control for the data):
- Ordered list → drag-and-drop handles (HTML5 drag API or a small inline impl)
- Branching logic → indented blocks with visible connectors / nesting
- Pairwise mapping → two columns + drop targets or dropdowns
- Tagging / set selection → chip pickers with add-on-Enter
- Numeric range or weight → slider with live label and units
- Constrained string → `<select>`; free string → `<input>`; rich → `contenteditable`
- Add / remove children → `+ row` and `×` affordances on hover
- Repeated structure → "duplicate this block" button

A 20-row table or generic JSON editor means you should redesign. The point of going custom is to fit the data shape.

### Invocation pattern

Call `Bash` in the foreground with `timeout: 600000` (10 min — the cap). Blocks until the user submits; stdout is the JSON.

```bash
TURN_ID="grill-cancellation-q1"
HTML="/tmp/in-html/${TURN_ID}.html"
ANSWER="/tmp/in-html/answers/${TURN_ID}.json"
mkdir -p /tmp/in-html/answers

# 1. Write $HTML (start from templates/feedback-turn.html, or build from scratch).
# 2. Launch foreground. Auto-opens browser; blocks until user submits.
#    stdout = answer JSON. (Tab stays open with a "Sent" panel; user closes it.)
bun ~/.claude/skills/in-html/feedback-server.ts \
    --file "$HTML" --answer "$ANSWER" --timeout 540
```

Parse the JSON from stdout. Continue the turn — ask the next question, update CONTEXT.md, write the config the data-shape produced, whatever the skill flow demands. **The user doesn't type anything in chat.**

### Escape hatch — longer waits or true async via a hook

For waits beyond 10 minutes (a real plan review, an AFK approval flow), Bash won't cut it — write a real hook the way plannotator does. Wire a `PermissionRequest` (or `Stop`, or custom-matcher) hook in `~/.claude/settings.json` that invokes `feedback-server.ts` and pipes the JSON to stdout. Hooks declare `"timeout": 345600` (96h) and block the turn the same way. Out of scope for this skill — see plannotator's `hooks/hooks.json` for the shape.

### Example — wiring this into grill-with-docs

Each grilling question becomes one foreground Bash call:

1. Agent picks the next unresolved branch ("you said 'account' — Customer or User?").
2. Agent assembles max context: relevant CONTEXT.md glossary entries, ambiguous code excerpt, related ADRs, the scenario being stress-tested.
3. Agent writes `/tmp/in-html/grill-<topic>-q<N>.html` from `templates/feedback-turn.html`: question title, context blocks marked `data-annotatable`, chips for likely answers, recommended-answer pre-fill, talk-more drawer.
4. Agent runs `feedback-server.ts` as a foreground Bash call. Browser tab auto-opens; the turn blocks.
5. User picks a chip or edits + Submit. Tab shows "✓ Sent"; server prints JSON to stdout, exits.
6. Agent parses stdout, updates CONTEXT.md if a term resolved, loops to step 1 — all in the same turn.

`grill-with-docs` doesn't need to be modified — opt in per session.

### What not to do

- **Don't reuse one HTML across turns.** Each interaction gets a fresh artifact with that turn's context.
- **Don't put the question in the chat *and* the HTML.** The HTML is the question. Chat just points to it.
- **Don't end your turn and ask the user to "say continue".** Run foreground so the same turn continues automatically after submit. That's the whole point.
- **Don't omit the clipboard fallback** in the template — if the server dies, the user can still recover the JSON by pasting.
- **Don't recreate this as a generic form.** Design the UI for the problem.

## Where to save

Default to `/tmp/in-html/<topic>.html` — these are one-off artifacts. Kebab-case names: `decision-rules.html`, `chat-routing-plan.html`, `grill-cancellation-q1.html`. Only save into the repo if the user asks for it.

## Boilerplate header

`templates/viz-scaffold.html` already bakes this in (plus the dark-mode toggle
and the common viz CSS: `.badge`/`.grid2`/`.add`/`.del`/`.callout`/`.num`/…) —
bootstrap from it instead of typing the head out. For reference, every artifact
starts with this `<head>`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{{topic}}</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css" />
  <style>
    /* artifact-specific tweaks only — Pico styles semantic HTML out of the box */
  </style>
</head>
```

**No `data-theme` on `<html>`** — leaving it off lets Pico follow the reader's
OS `prefers-color-scheme` (light *or* dark) instead of forcing light. In your
artifact-specific `<style>`, use Pico CSS variables (`var(--pico-...)`) rather
than hardcoded colors (`white`, `#fff`, `#1a1a1a`) so both themes look right.

Wrap page content in `<main class="container">`. Pico styles semantic HTML with no classes — `<article>` (cards), `<table>`, `<details>`/`<summary>`, `<input>`/`<select>`/`<button>`, `<kbd>`, `<hgroup>`, `<nav>`. Use the `<style>` block for the few problem-specific bits (segmented controls, fixed buttons, custom layout). If an artifact genuinely needs heavy utility-class layout, swapping in Tailwind (`<script src="https://cdn.tailwindcss.com">`) is a fine escape hatch — Pico is the default, not a hard rule.

## Dark mode

With no `data-theme` set, Pico already follows the OS preference. Add this
toggle (near the top of `<body>`) so the reader can also flip it manually; the
choice persists in `localStorage`, and clearing it falls back to system pref.
The `localStorage` access is wrapped in try/catch — it throws a `SecurityError`
on `file://` (opaque origin), and without the guard the whole handler dies and
the button does nothing. With the guard the toggle still flips in-session; it
just can't persist on `file://`. The snippet uses no backticks, so it's safe to
embed even when the artifact gets posted inside an `x-html` fence (see the
`in-html-gh` skill).

```html
<button id="theme-toggle" class="contrast" aria-label="Toggle dark mode"
        style="position:fixed;top:.5rem;right:.5rem;padding:.2rem .5rem">🌓</button>
<script>
  (function () {
    var root = document.documentElement;
    function load() { try { return localStorage.getItem('theme'); } catch (e) { return null; } }
    function save(v) { try { localStorage.setItem('theme', v); } catch (e) {} }
    var saved = load();                               // 'light' | 'dark' | null = follow system
    if (saved) root.setAttribute('data-theme', saved);
    document.getElementById('theme-toggle').addEventListener('click', function () {
      var cur = root.getAttribute('data-theme')
        || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
      var next = cur === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      save(next);
    });
  })();
</script>
```

## Secure context — Mode 1 artifacts that need browser permissions

(Mode 2 already runs on `http://localhost:<port>` so it's a secure context automatically.)

A `file://` artifact is an opaque origin: Chrome never persists permission grants for it (microphone, camera, clipboard-read), so it re-prompts on *every* use. `http://localhost:<port>` *is* a secure context on every platform (Chrome treats `localhost` as potentially trustworthy), so just serving the file there already unlocks the permission prompts.

When a Mode 1 artifact uses `getUserMedia`, the Web Speech API, persistent clipboard read, etc., serve it instead of `xdg-open`/`open`-ing the `file://` path:

```bash
cd /tmp/in-html
(python3 -m http.server 8777 &)     # any static server / port — works on macOS & Linux
```

Open `http://localhost:8777/<file>.html`. That's enough for permissions to work; the catch is that the *port* is part of the origin, so a grant doesn't carry to a different port.

To make grants **persist across artifacts/sessions**, give them a stable origin:

- **Linux:** `http://*.localhost` resolves automatically, so a reverse proxy with a fixed hostname works — e.g. `portless alias in-html 8777` (then open `http://in-html.localhost:<proxy-port>/<file>.html`). Reuse the one `in-html` alias for every artifact; they share the origin and therefore one grant.
- **macOS:** `*.localhost` does **not** auto-resolve. Either keep one fixed port (`--port 8777` every time, so the `localhost:8777` origin is stable), or add a hosts entry — `echo '127.0.0.1 in-html.localhost' | sudo tee -a /etc/hosts` — and point any proxy (`caddy reverse-proxy --from in-html.localhost:80 --to :8777`, etc.) at it.

For artifacts that need no permissions, plain `xdg-open`/`open` of the `file://` path stays the default.

## Anti-patterns

- **Don't depend on external assets** beyond well-known CDNs (Pico, mermaid). The file must be portable.
- **Don't summarize the artifact in chat after writing.** The HTML *is* the artifact. Just point to it.
- **Don't reach for Mode 2 when Mode 1 is enough.** A plan you only need to *show* doesn't need a server. Run the server only when you need data back.
