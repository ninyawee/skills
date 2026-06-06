---
name: in-html-gh
description: >-
  Generate a self-contained HTML visualization the same way /in-html viz mode
  does, then publish it directly to a GitHub issue or PR — either as a new
  comment (default), appended to the body, or replacing the body — using the
  gh-x-html Chrome extension's `x-html` fenced code block for inline rendering.
  Use this skill whenever the user wants to build *and* share an HTML viz on
  GitHub in one step — phrases like "/in-html-gh <topic> to issue #N", "viz
  this and post it on PR #N", "build me a decision matrix and drop it on issue
  #N", "in-html this but post to github", "make an html breakdown of X and put
  it in the issue body", "render the rollout plan inline on issue #N", or any
  ask that combines "generate HTML" + "share via GitHub". Composes the
  /in-html generation logic with the gh-x-html posting pattern in one skill so
  the user never has to mention both. Posts a layered body so every reader gets
  something legible — an inline `x-html` fence (rendered for reviewers with the
  gh-x-html extension), a full-HTML click-through link hosted on R2 (host-file)
  for everyone else, and a collapsed `<details>` markdown fallback — and the
  generated HTML carries a dark-mode toggle that defaults to the system
  preference. For deterministic invocation (typing `/in-html-gh <args>`), use
  the slash command of the same name at `~/.claude/commands/in-html-gh.md` — it
  routes through this skill.
---

# in-html-gh

One skill, two halves: **build the HTML viz** (same patterns as /in-html viz
mode) and **post it to a GitHub target** (issue body, PR body, or comment).
The two used to be separate steps; this skill chains them so the user can say
"/in-html-gh decision matrix for the runner migration → issue #932" and get a
comment URL back in one round-trip.

The reason this collapse is worth doing: every time the user generates an
HTML for a teammate, the next move is to put it on GitHub. Asking them to run
two skills or remember a wrapper command adds friction with no payoff. The
chained skill defaults to safe behavior (post as a comment, leave the body
alone) but exposes body-edit modes when the viz IS the issue/PR description.

## What it does

1. **Generate** — Build a single self-contained `.html` file using the same
   patterns as `/in-html` viz mode. Use Pico CSS via CDN, semantic HTML, and
   inline SVG / mermaid only when a diagram earns its keep. **Include the
   dark-mode toggle** (snippet below) — it defaults to the reader's system
   preference. Save to `/tmp/in-html/<topic>.html`. Alongside it, write a plain
   **`/tmp/in-html/<topic>.md`** — a short markdown rendition of the same
   content (headings, tables, key bullets) for the collapsed `<details>`
   fallback; `post.sh` auto-detects this sibling. Do **not** open the HTML in
   the browser — the reviewer's preview is on GitHub, not the local machine.
2. **Validate** — Run `scripts/post.sh` with the right mode; the script
   refuses on triple-backtick collisions inside the HTML (would close the
   x-html fence early). If the assembled body exceeds GitHub's 65,536-char
   ceiling it automatically drops the inline fence and falls back to the
   full-HTML link + `<details>` (so it still posts).
3. **Publish** — Host the full HTML on R2 (host-file) for a click-through link,
   then comment / append / replace the body via the appropriate
   `gh issue/pr comment | edit` invocation. The posted body has three layers
   (see **Posted body layout** below). Return the resulting URL.

Refer to the `/in-html` skill's "Mode 1 — viz" section for the generation
patterns (code excerpts with file:line captions, decision tables, side-by-side
panels, `<details>` for long blocks, mermaid for diagrams that benefit, Pico
boilerplate header). Don't duplicate that material here — read it from
`/in-html` and apply.

## Posted body layout

Every post is layered so it degrades gracefully — no reviewer is left staring
at raw HTML or a dead link:

1. **` ```x-html ` fence** — the full HTML. Renders inline for reviewers who
   have the gh-x-html extension installed and the author allowlisted. Dropped
   automatically if the assembled body would exceed 65,536 chars.
2. **📄 full-HTML link** — the HTML hosted on R2 via `host-file`, so any
   reviewer can open the fully-rendered, JS-enabled page (dark-mode toggle,
   mermaid, sortable tables) in a new tab. Tier is `permanent` by default
   (`--host-tier ephemeral` for a 30-day link, `none` to skip hosting).
3. **`<details>Details</details>`** — a collapsed plain-markdown rendition
   (the `<topic>.md` sibling). Always legible, even with no extension and no
   click-through. Code fences inside it are fine — it sits outside the x-html
   fence.

> Privacy note: layer 2 puts the HTML on a **public** (unguessable) R2 URL —
> a step outside the private-repo boundary. Fine for design/plan/status vizzes;
> for anything with secrets or customer PII, pass `--host-tier none` and rely on
> the inline fence + `<details>` only.

## Dark-mode toggle

Drop this near the top of `<body>` in the generated HTML. With no `data-theme`
set, Pico follows the OS `prefers-color-scheme`; the button flips and persists
an explicit choice. (The toggle's JS runs in the R2-hosted full page; inside
the inline `x-html` fence it may be static — that's fine, the page still
respects system dark mode.)

```html
<button id="theme-toggle" class="contrast" aria-label="Toggle dark mode"
        style="position:fixed;top:.5rem;right:.5rem;padding:.2rem .5rem">🌓</button>
<script>
  (function () {
    var root = document.documentElement;
    // localStorage throws on file:// (opaque origin) — guard so the toggle still works.
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

## Usage

```bash
~/.claude/skills/in-html-gh/scripts/post.sh <html-file> <gh-ref> \
  [--mode comment|body-append|body-replace] \
  [--intro <md-file>|--intro-text "..."] \
  [--md <md-file>] [--host-tier permanent|ephemeral|none] [--yes]
```

The script handles ref parsing (full URL, `owner/repo#N` short form, `#N`
against current git remote, `:pr` suffix for PRs), mode dispatch, fence
collision guards, R2 hosting of the full HTML, the `<details>` markdown
fallback (`--md`, or an auto-detected `<html-basename>.md` sibling), the
size-driven fence drop, and per-mode confirmation. `--host-tier` controls the
full-HTML link: `permanent` (default), `ephemeral` (30-day), or `none` (skip).
The mode determines which `gh` endpoints it calls:

| Mode | What happens | When to use |
|---|---|---|
| `comment` (default) | Adds a new comment to the issue/PR. Leaves the existing body untouched. | Almost always — comments are non-destructive, get their own anchor URLs, and read cleanly in the timeline. |
| `body-append` | Fetches the existing body, appends two blank lines + the fenced HTML, edits the body. | When the issue/PR description should *grow* into a multi-viz document over time. |
| `body-replace` | Overwrites the existing body with just the fenced HTML (plus intro if given). Confirms interactively, or requires `--yes`. | When you're creating a fresh issue/PR where the viz IS the description. Rarely the right call after the issue/PR is established. |

`body-replace` is destructive — it overwrites the existing body. The script
prints the old/new byte counts and prompts unless `--yes` is given (or stdin
isn't a tty, in which case it refuses for safety).

### Examples

Posting a freshly-built viz as a new comment on an existing issue:

```bash
# After generating the HTML in /tmp/in-html/runner-migration-matrix.html:
~/.claude/skills/in-html-gh/scripts/post.sh \
  /tmp/in-html/runner-migration-matrix.html \
  https://github.com/ninyawee/pakjai/issues/932 \
  --intro-text "## Decision matrix viz

The per-workflow matrix from the analysis. Sortable-ish table, color-coded recommendations."
```

Appending a viz to a PR description so the description grows into a
multi-artifact spec:

```bash
~/.claude/skills/in-html-gh/scripts/post.sh \
  /tmp/in-html/design-walkthrough.html \
  ninyawee/codustry#42:pr \
  --mode body-append \
  --intro ./walkthrough-context.md
```

Creating an issue body that IS the viz (paired with `gh issue create`):

```bash
# Compose body from a small markdown header + the fenced HTML, replace the
# placeholder body in one shot.
~/.claude/skills/in-html-gh/scripts/post.sh \
  /tmp/in-html/migration-status-dashboard.html \
  ninyawee/pakjai#1042 \
  --mode body-replace --yes --intro-text "## Migration status dashboard"
```

### Output

- **stdout** — the URL of the resulting comment (for `comment` mode) or the
  issue/PR (for `body-*` modes). Always surface this URL so the user can
  click through.
- **stderr** — short status line per mode (`comment on owner/repo#N (issue,
  23379 bytes)` or `body-append body of owner/repo#N (pr, 4120 → 27543
  bytes)`) and any error messages.

## When to use this vs. plain /in-html

Reach for **`/in-html-gh`** when:

- The user is going to share the viz on GitHub anyway — explicitly ("post to
  #N") or implicitly ("the team needs to see this"; "frank will review on
  github").
- The content has internal infrastructure detail, customer counts, or other
  fingerprints you wouldn't want crawl-indexed. The private-repo boundary is
  the right boundary; R2 public hosting isn't.
- The audience is small + allowlisted; reviewers who have the gh-x-html
  extension installed get the rendered version, reviewers without it see
  legible HTML source — both are acceptable.

Reach for **`/in-html` alone** when:

- The viz is for the user's own consumption — they want to play with the
  artifact, drill into a `<details>`, see a table. No teammate involvement.
- The viz needs interactive feedback (`/in-html` feedback mode); that's
  outside this skill's scope.
- The HTML will go somewhere other than GitHub (a static site, a Slack
  upload, a PDF export).

When in doubt, default to `/in-html` and let the user decide whether to share.
But if the user mentions a specific issue/PR/audience on GitHub, `/in-html-gh`
is the right choice.

## What this does NOT replace

- **A static thumbnail when you want one always-visible inline.** Non-extension
  reviewers are already covered by the full-HTML link + the `<details>`
  markdown, so a screenshot is no longer the *fallback* — but if you want an
  image that renders inline with zero clicks, take a PNG of the HTML and
  `host-file` it (R2), then `![alt](<r2-url>)`. (Don't commit to
  `docs/screenshots/` on a private repo — `raw.githubusercontent.com` only
  renders for logged-in collaborators.)
- **`host-file` directly for non-HTML files.** This skill already calls
  `host-file` for the HTML; for PNGs, videos, and logs, call `host-file`
  yourself — they need real hosting, not an `x-html` fence.
- **`/in-html` feedback mode.** That needs a local server to receive
  structured JSON from the user. GitHub can render content but can't run a
  server, so the feedback flow doesn't translate.

## Edge cases the script guards against

1. **Triple-backtick inside the HTML** — would close the `x-html` fence early.
   The script greps for ` ``` ` before posting and refuses with the offending
   lines listed. Escape inside `<code>` blocks (`&#96;&#96;&#96;`) or split
   the HTML.
2. **Combined body over 65,536 chars** — GitHub's per-comment/body ceiling.
   For comment mode that's just the fenced block; for body-append it's
   existing-body + the fenced block. The script computes the assembled size
   before posting.
3. **Wrong endpoint kind (issue vs PR)** — GitHub treats them as separate
   APIs. The script parses `/issues/` vs `/pull/` from URLs, accepts a `:pr`
   suffix on short refs, and defaults to `issue` for ambiguous refs.
4. **Destructive body-replace without confirmation** — the script prints
   old/new byte counts and prompts when stdin is a tty; refuses with a hint
   to pass `--yes` when stdin isn't (e.g. when called from another agent).

## Multiple HTMLs on the same issue/PR

Don't pack two HTMLs into one comment by stacking two `x-html` fences. Post
each one separately:

```bash
post.sh ./matrix.html ninyawee/pakjai#932 --intro-text "## Matrix"
post.sh ./cache-explainer.html ninyawee/pakjai#932 --intro-text "## How the cache rerouting works"
```

Two separate `gh issue comment` calls → two anchor URLs → reviewers can reply
to "the matrix" separately from "the cache explainer" without confused
threading. The 65,536-char limit applies per comment so one big comment hits
the ceiling much sooner.

## Reviewer-side requirements

The viz renders inline for reviewers who:

1. Have the **gh-x-html Chrome extension** installed
   (https://github.com/ninyawee/gh-x-html).
2. Have **the commenter's GitHub login on their allowlist** (seeded at
   install, stored in `chrome.storage.sync`). If the user posted via a bot
   account or PAT for a different login, reviewers may need to add that
   login.

Reviewers without the extension don't get the inline render, but they're not
stuck: the body also carries the **📄 full-HTML link** (the complete rendered
page on R2 — JS, mermaid, dark-mode toggle and all) and the collapsed
**`<details>` markdown** (always legible, zero clicks). The link covers the
"I want the rendered view" case; the `<details>` covers the "I won't click
out" case. A screenshot is only worth it when you want an always-visible
inline image (see "What this does NOT replace").
