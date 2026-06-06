---
description: Build an HTML viz (using /in-html viz patterns) and publish it inline to a GitHub issue or PR via the gh-x-html `x-html` fence — comment by default, or `--mode body-append` / `--mode body-replace`.
---

# /in-html-gh

Build a self-contained HTML visualization for the topic in `$ARGUMENTS`, then publish it to the indicated GitHub issue or PR using the gh-x-html `x-html` fenced code block pattern. Two halves in one command: generate (same patterns as `/in-html` viz mode) + post.

## Workflow

Follow the `in-html-gh` skill at `~/.claude/skills/in-html-gh/SKILL.md` for the full reasoning, edge cases, and reviewer-side requirements. The mechanical steps:

1. **Parse `$ARGUMENTS`** for two things — the topic of the viz and the GitHub destination (issue/PR ref). If either is missing, ask the user before generating anything. Don't guess the target ref.

2. **Generate the HTML** using `/in-html` viz-mode patterns — Pico CSS via CDN with SRI, semantic HTML, inline SVG only when a diagram earns its keep, mermaid only when the diagram benefits and you can pin a known integrity hash. **Include the dark-mode toggle** from the skill's "Dark-mode toggle" section (defaults to system preference). Save to `/tmp/in-html/<topic-kebab-case>.html`, and write a short plain-markdown rendition of the same content to `/tmp/in-html/<topic-kebab-case>.md` (the `<details>` fallback; `post.sh` auto-detects the sibling). Do **not** open the HTML in a browser — the reviewer's preview is on GitHub, not the local machine.

3. **Publish** via the bundled helper:
   ```bash
   ~/.claude/skills/in-html-gh/scripts/post.sh \
     <html-path> \
     <gh-ref> \
     [--mode comment|body-append|body-replace] \
     [--intro-text "..." | --intro <md-file>] \
     [--md <md-file>] [--host-tier permanent|ephemeral|none] [--yes]
   ```
   It hosts the full HTML on R2 (host-file) for a click-through link, and posts a layered body: inline `x-html` fence + full-HTML link + collapsed `<details>` markdown. Default `--mode` is `comment` — non-destructive, gets its own anchor URL, almost always the right call. Only reach for `body-append` when the issue/PR description should grow into a multi-viz document; only reach for `body-replace` when the viz IS the description (and the user has been explicit about wanting to overwrite). Pass `--host-tier none` for content with secrets/PII (skips the public R2 link).

4. **Return the URL** the script prints on stdout so the user can click through and verify the render.

## Argument shape

`$ARGUMENTS` typically looks like one of:

- `decision matrix for the runner migration → ninyawee/pakjai#932`
- `comparison viz of the 3 chat-routing strategies → admin-panel PR #1156`
- `architecture-walkthrough for the supabase migration ordering bug → issue 738 (body-replace)`

If the user gives you a `mode` hint (e.g., "drop it in the body", "append to the description"), translate it to the matching `--mode` flag. If they give you a custom intro line, pass it as `--intro-text`.

## When to fall back

- HTML too large to inline → `post.sh` auto-drops the `x-html` fence and keeps the full-HTML link + `<details>` (so it still posts). If even that's over the 64KB body limit, split into smaller visualizations and post each separately (the skill's "Multiple HTMLs" section).
- Reviewers without the extension → already covered: the body carries the full-HTML R2 link + the `<details>` markdown. Only add a static `host-file`'d PNG if you want an always-visible inline image.
- Content with secrets / customer PII → pass `--host-tier none` so the full HTML isn't put on the public R2 URL; reviewers then rely on the inline fence + `<details>` only.
