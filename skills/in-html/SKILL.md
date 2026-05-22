---
name: in-html
description: Create a single self-contained HTML artifact to either visualize an implementation plan (read-only — code excerpts, mockups, diagrams, decisions, tradeoffs) or to let the user shape structured data through a custom HITL interface (editable forms, drag-drop, sliders, chips, tree editing — with copy-result-as-JSON). Use when the user asks for an HTML plan, an HTML visualization of an implementation, an editable HTML artifact, a HITL UI to define rules / configs / decisions, "design the ideal interface for this problem", or invokes /in-html. Output is one .html file saved to /tmp/in-html/, Pico CSS via CDN, auto-opened in the browser.
---

# in-html

Two modes, one goal: give the user *maximum context in a glanceable form*, or let them *shape structured data through the best possible UI for the problem*.

Pick one mode per file — don't mix.

## Quick start

1. Pick a mode — **viz** (read-only plan) or **editable** (HITL).
2. Pick a path beside the related code (see "Where to save").
3. Write one self-contained `.html` — Pico CSS via CDN, vanilla JS, no build, no framework.
4. `xdg-open` it and print the absolute path.

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

## Mode 2 — Editable / HITL

For: "design the ideal interface for this problem" — when the user wants to *shape* structured data (decision rules, routing/mapping, prioritization, config trees, content schemas, taxonomy) and the existing UIs feel wrong.

**Design the UI for the problem, not from a generic form template.** If the result looks like a JSON editor or a 20-row table, redesign. Pick controls that match the *shape of the data*:

- Ordered list → drag-and-drop handles (use the HTML5 drag API or a small inline impl)
- Branching logic → indented blocks with visible connectors / nesting
- Pairwise mapping → two columns + drop targets or dropdowns
- Tagging / set selection → chip pickers with add-on-Enter
- Numeric range or weight → slider with live label and units
- Constrained string → `<select>`; free string → `<input>`; rich → `contenteditable` div
- Add / remove children → `+ row` and `×` affordances on hover
- Repeated structure → "duplicate this block" button

**Always include a "Copy result" button** that serializes the live UI state to JSON and writes it to the clipboard. Show a live JSON preview (read-only `<pre>`) so the user sees what they're about to copy — update on every change. Snippet to drop in once:

```html
<button id="copy-result">Copy result</button>
<style>
  /* Pico styles the button itself; this only pins it to the corner. */
  #copy-result { position: fixed; right: 1rem; bottom: 1rem; width: auto; margin: 0; z-index: 50; }
</style>
<script>
  function buildResult() {
    // Read the live UI and return the JSON shape that represents it.
    // Customize per artifact.
    return { /* ... */ };
  }
  function renderPreview() {
    const p = document.getElementById('result-preview');
    if (p) p.textContent = JSON.stringify(buildResult(), null, 2);
  }
  document.addEventListener('input', renderPreview);
  document.addEventListener('change', renderPreview);
  document.addEventListener('click', renderPreview);
  document.getElementById('copy-result').addEventListener('click', async () => {
    await navigator.clipboard.writeText(JSON.stringify(buildResult(), null, 2));
    const b = document.getElementById('copy-result');
    const orig = b.textContent;
    b.textContent = 'Copied ✓';
    setTimeout(() => (b.textContent = orig), 1200);
  });
  renderPreview();
</script>
```

Define the JSON shape *first* — write it as a comment at the top of the file — then design the UI as the inverse of that shape. The user will paste the JSON back to you; make sure it's something you can actually consume on the next turn.

## Where to save

Default to `/tmp/in-html/<topic>.html` — these are one-off artifacts. Kebab-case names: `decision-rules.html`, `chat-routing-plan.html`. Only save into the repo if the user asks for it.

## Boilerplate header

Every artifact starts with this `<head>`:

```html
<!doctype html>
<html lang="en" data-theme="light">
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

Wrap page content in `<main class="container">`. Pico styles semantic HTML with no classes — `<article>` (cards), `<table>`, `<details>`/`<summary>`, `<input>`/`<select>`/`<button>`, `<kbd>`, `<hgroup>`, `<nav>`. Use the `<style>` block for the few problem-specific bits (segmented controls, fixed buttons, custom layout). If an artifact genuinely needs heavy utility-class layout, swapping in Tailwind (`<script src="https://cdn.tailwindcss.com">`) is a fine escape hatch — Pico is the default, not a hard rule.

## Auto-open

After writing, run once:

```bash
xdg-open /abs/path/to/file.html 2>/dev/null || open /abs/path/to/file.html 2>/dev/null || true
```

Then print the absolute path on its own line so the user can re-open / share it.

## Secure context — artifacts that need browser permissions

A `file://` artifact is an opaque origin: Chrome never persists permission grants for it (microphone, camera, clipboard-read), so it re-prompts on *every* use. `http://*.localhost` *is* a secure context — grants persist there.

When the artifact uses `getUserMedia`, the Web Speech API, persistent clipboard read, etc., serve it through `portless` instead of `xdg-open`-ing the `file://` path:

```bash
cd /tmp/in-html
(python3 -m http.server 8777 &)     # any static server / port
portless alias in-html 8777         # stable alias; `portless list` shows the proxy port + URL
```

Open `http://in-html.localhost:<proxy-port>/<file>.html`. Reuse the one `in-html` alias for every artifact — they share the `in-html.localhost` origin and therefore one permission grant, which is intended and fine. For artifacts that need no permissions, plain `xdg-open` of the `file://` path stays the default.

## Anti-patterns

- **Don't recreate this as a generic form.** The point of editable mode is a UI *designed for the problem*. Generic form → redesign.
- **Don't depend on external assets** beyond well-known CDNs (Pico, mermaid). The file must be portable.
- **Don't add a server, build step, or framework.** Single static `.html`. Vanilla JS.
- **Don't omit the copy-back affordance** in editable mode — without it, the user's edits never reach you.
- **Don't summarize the plan in chat after writing.** The HTML *is* the artifact. Just point to it.
