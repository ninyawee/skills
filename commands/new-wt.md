---
description: Create a new git worktree for a feature/fix, bootstrap it per the project's conventions, and open it in VS Code
argument-hint: <what to do> [base-branch — default develop]
version: 1.0.0
---

# New Worktree

Spin up a fresh git worktree on a new branch, bootstrap it the way this repo expects, and open it in VS Code (`code`). This command only **sets up** the worktree — it does not start doing the work inside it.

## Input

`$ARGUMENTS` = `<what to do>` plus an optional trailing base branch.

- **WHAT** — short description of the feature/fix the worktree is for. May carry an explicit conventional-commit-style prefix (`feat:`, `fix:`, `hotfix:`, `docs:`, `chore:`, `refactor:`).
- **BASE** — the *last* whitespace-delimited token, **only if** it names an existing local or remote branch (e.g. `main`, `develop`). Otherwise there is no explicit base → **default `develop`**. Strip it off `WHAT` once consumed.

## Steps

### 1. Derive branch name + worktree path

- **Branch type**: explicit prefix in `WHAT` wins; else `fix/` if `WHAT` mentions fix/hotfix/bug, `docs/` for docs, otherwise `feat/`.
- **Slug**: kebab-case of `WHAT` with the prefix and filler words (`feat`, `feature`, `the`, `a`) stripped; keep it ~2–4 words. → branch = `<type>/<slug>` (shorten the slug only if it's unwieldy).
- **Worktree dir**: match whatever pattern the repo already uses — run `git worktree list` and look at sibling worktrees. Common patterns:
  - `<repo-root>.wt.<short-slug>` as a sibling of the main checkout (e.g. this Pakjai repo) — prefer this if present.
  - else `<parent-of-root>/<repo-basename>-<short-slug>`.
  Keep `<short-slug>` shorter than the branch slug if the branch slug is long.
- Show the user the chosen branch name + path before creating (one line, no need to ask permission unless something's ambiguous).

### 2. Create the worktree from an up-to-date base

```bash
ROOT=$(git rev-parse --show-toplevel)
git -C "$ROOT" fetch origin "<BASE>" --quiet
git -C "$ROOT" worktree add "<WORKTREE_DIR>" -b "<BRANCH>" "origin/<BASE>"
```

Base off `origin/<BASE>` (not the possibly-stale local branch). If the branch already exists, stop and ask.

### 3. Bootstrap the worktree per the project's conventions

Read the new worktree's `CLAUDE.md` (and any `README`/`mise.toml`) for a "Worktree Setup" / bootstrap section and follow it. For this repo (Pakjai) that is, run from the new worktree root:

```bash
mise run trust        # if it fails on a path that doesn't exist on this base branch
                      #   (e.g. backends/chatbot), trust the existing subdirs manually:
                      #   mise -C frontends/admin-panel trust; mise -C frontends/liff trust;
                      #   mise -C backends/line-collectors trust
mise install          # pinned tools (hk, bun, …)
mise run setup-hk     # git hooks (pre-push/pre-commit) — a core.hooksPath warning is expected in worktrees
mise run init         # JS deps for all sub-projects
```

If the repo has no documented bootstrap: just install deps with the project's package manager (`bun install` / `uv sync` / `pnpm i` …) and skip the rest.

Do **not** run `mise run wt:init` (Supabase port isolation) — it's opt-in. Mention it as available if the work needs an isolated Supabase instance.

### 4. Open in VS Code

```bash
code "<WORKTREE_DIR>"
```

## Result

- New worktree at `<WORKTREE_DIR>` on branch `<BRANCH>`, based on `origin/<BASE>`.
- Dependencies + git hooks installed.
- VS Code opened on it.
- Report: branch, path, base, what bootstrap ran, and any warnings/skips (e.g. `trust` task partial failure, `wt:init` not run).

## Examples

```bash
/new-wt n8n chatroom tag append feat main      # branch feat/n8n-chatroom-tag-append off origin/main
/new-wt fix: liff finder bangkok fallback      # branch fix/liff-finder-bangkok-fallback off origin/develop
/new-wt posthog ultrasound embed tracking      # branch feat/posthog-ultrasound-embed-tracking off origin/develop
```
