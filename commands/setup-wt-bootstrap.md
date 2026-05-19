---
description: Set up a repo so `git worktree add` auto-bootstraps the new worktree (mise `wt:bootstrap` task + a shared `post-checkout` git hook)
argument-hint: "[overrides — e.g. 'secrets file is .env.local', 'pkg manager pnpm']"
version: 1.0.0
---

# Set up worktree auto-bootstrap

Make `git worktree add` (and `git clone`) leave a worktree **ready to use** with zero manual steps: a shared `post-checkout` git hook runs a `mise run wt:bootstrap` task that trusts the mise configs, copies the machine-local secrets file from the main checkout, installs tools + deps, and installs the git hooks. Adapt every step to *this* repo's layout — the snippets below are the pattern, not a literal script.

`$ARGUMENTS` (optional) = free-text overrides — e.g. the machine-local secrets filename, the package manager, which sub-projects to bootstrap. Honour them; otherwise auto-detect.

## 0. Preconditions — bail or adapt

- Must be inside a git repo (`git rev-parse --show-toplevel`). If not → stop, tell the user.
- This pattern is **mise-centric**. If there's no root `mise.toml`: ask whether to add a minimal one (`[tools]` + a `[tasks.init]` that installs deps) or abort — don't force it.
- Resolve the hooks dir once: `HOOKS_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"`. If `git config core.hooksPath` is set to a *custom* dir (husky / lefthook / …), put the hook **there** instead and warn that it may interact with that tool. If `core.hooksPath` is *relative*, warn that it silently breaks across worktrees (flag it; don't fix it unilaterally).

## 1. Detect the moving parts (show the user a one-line summary before changing anything)

- **Sub-projects with their own `mise.toml`** — `git ls-files | grep '/mise\.toml$'` plus `find . -maxdepth 3 -name mise.toml -not -path '*/node_modules/*'`. These get `mise -C <dir> trust` and, if they have an `init` task, `mise -C <dir> run init`.
- **Machine-local secrets file** — the gitignored, never-committed, per-machine file:
  - `fnox.toml` present → `fnox.local.toml` (fnox auto-merges it alongside `fnox.toml` — nothing else needed to load it).
  - else `.env` / `.env.example` present → `.env.local` (or whatever the repo already references).
  - else `mise.local.toml` if that's where the repo keeps machine-local env.
  - else → no secrets-copy step. State which it picked; ask if genuinely ambiguous.
- **Hook manager** — `hk.pkl` → expect (or add) a `setup-hk` task. `lefthook.yml` / `.husky/` / `.pre-commit-config.yaml` → note the overlap; we still install our own `post-checkout`.
- **Dep install** — prefer an existing root `[tasks.init]`. Else compose from detected managers: `bun install` (bun + `package.json`), `pnpm i`, `npm ci`/`npm i`, `uv sync` (`pyproject.toml`), `cargo fetch`, `go mod download`, … run in the root and/or each sub-project.
- **Docs file** — `CLAUDE.md` / `AGENTS.md` / `README` — where worktree/setup notes live (or should).

## 2. Add `[tasks."wt:bootstrap"]` to the root `mise.toml` (idempotent — update in place if present)

Adapt the dir lists / secrets file / dep commands to step 1. Omit the secrets block if no secrets file; omit `mise run setup-hk` if there's no hook-install task (then inline the hook-write — see step 3).

```toml
[tasks."wt:bootstrap"]
description = "Make a freshly-created worktree ready to use (trust + machine-local secrets + tools/deps + git hooks)"
# Auto-run by the `post-checkout` git hook on `git worktree add` (installed by `mise run setup-hk`,
# lives in the shared $GIT_COMMON_DIR/hooks). By hand: `mise trust && mise run wt:bootstrap`.
# Every step `|| true` so an offline machine / missing source can't half-break the worktree or
# abort `git worktree add` (a non-zero post-checkout makes it report failure).
run = '''
mise trust >/dev/null 2>&1 || true
for d in <SUB_PROJECT_DIRS>; do
  [ -f "$d/mise.toml" ] && (mise -C "$d" trust >/dev/null 2>&1 || true)
done
# machine-local secrets (gitignored) — copy from the main checkout; on a fresh `git clone`
# the main checkout *is* PWD → nothing to copy → skip.
MAIN=$(git worktree list --porcelain 2>/dev/null | awk 'NR==1{print $2}')
if [ -n "${MAIN:-}" ] && [ "$MAIN" != "$PWD" ] && [ -f "$MAIN/<SECRETS_FILE>" ] && [ ! -e <SECRETS_FILE> ]; then
  cp "$MAIN/<SECRETS_FILE>" <SECRETS_FILE> && echo "🔑 copied <SECRETS_FILE> from $MAIN"
fi
mise install || true
mise run setup-hk || true
<DEP_INSTALL — e.g. `mise run init || true`, or `bun install || true`, …>
echo "✅ worktree ready: $PWD"
'''
```

## 3. Install the `post-checkout` hook — via the hook-setup task

**Why a plain hook, not an `hk.pkl` `["post-checkout"]` (or any hook-manager-wrapped hook):** hk installs it as `exec mise x -- hk run post-checkout …`, and `mise x` *errors outright* in an untrusted brand-new worktree (it doesn't degrade to global config) → the bootstrap never runs. A plain hook that `mise trust`s first sidesteps that, and gets git's `$1 $2 $3` directly for the "only on worktree-add" guard (hk doesn't expose those to step commands).

- Repo has a `[tasks.setup-hk]` (or equivalent hook-install task) → **append** the hook-write to its `run`.
- Has a hook manager but no such task → add `[tasks.setup-hk] run = "<hook-mgr install cmd>; <hook-write>"`.
- No hook manager → add `[tasks."setup-git-hooks"]` that just does the hook-write, and reference *that* name in `wt:bootstrap`'s `mise run …` line.

Hook-write snippet to append to that task's `run`:

```sh
HOOKS_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"   # or the custom core.hooksPath
mkdir -p "$HOOKS_DIR"
cat > "$HOOKS_DIR/post-checkout" <<'HOOK'
#!/bin/sh
# Auto-bootstrap a freshly-created worktree. Args: <prev-HEAD> <new-HEAD> <is-branch-checkout>.
# Managed by `mise run setup-hk` — do not edit by hand.
case "$1" in '' | *[!0]*) exit 0 ;; esac   # only when prev-HEAD is the null SHA → worktree-add / clone
[ "$3" = "1" ] || exit 0                    # only branch checkouts, not `git checkout -- <file>`
echo "🌱 New worktree detected — bootstrapping ($PWD)…"
mise trust >/dev/null 2>&1 || true
mise run wt:bootstrap || true
exit 0
HOOK
chmod +x "$HOOKS_DIR/post-checkout"
```

(Substitute the task names if you used different ones. The hook file is *generated*, not version-controlled — re-created by the hook-setup task, which `wt:bootstrap` calls, so it self-propagates.)

## 4. gitignore the machine-local secrets file

If step 1 picked one and it isn't already ignored: add it to `.gitignore` (next to similar entries) **and** append it to `"$(git rev-parse --git-common-dir)/info/exclude"` so existing worktrees ignore it immediately.

## 5. Document it

In the docs file (step 1), add/update a "Worktree Setup" / "Bootstrap a new worktree" section: `git worktree add` auto-bootstraps via the shared `post-checkout` hook → `mise run wt:bootstrap`; list what it does; manual fallback `mise trust && mise run wt:bootstrap`; `--no-checkout` skips the hook; the secrets file is gitignored and copied from the main checkout.

## 6. Activate + verify

- Run the hook-install task now (`mise run setup-hk` / `mise run setup-git-hooks`) so `post-checkout` is live.
- Guard check: `sh "$HOOKS_DIR/post-checkout" <a-real-sha> <sha> 1` → silent, exit 0; `sh "$HOOKS_DIR/post-checkout" 0000000000000000000000000000000000000000 <sha> 0` → silent, exit 0. Only `0000…0 <sha> 1` should fire.
- Optionally `mise run wt:bootstrap` in the current worktree (idempotent — cp skipped if the file exists, dep installs no-op with warm caches).
- A full proof needs a throwaway `git worktree add --detach …` (runs the whole bootstrap incl. dep installs) then `git worktree remove --force` — do it only if the user asks.

## 7. Report

- What you detected (sub-projects, secrets file, hook manager, dep commands).
- Files changed (`mise.toml`, `.gitignore`, docs, …) and the hook installed at `<path>`.
- Changes are **not** committed (don't commit/PR unless asked). Caveat: the hook calls `mise run wt:bootstrap`, which only exists on commits carrying the `mise.toml` change — until that lands on the default/develop branch, worktrees off other branches will see the hook print its message then harmlessly no-op. Recommend committing the `mise.toml` change to the default branch.
- Anything skipped/ambiguous (no secrets file, custom/relative `core.hooksPath`, hook-manager overlap, no `mise.toml`, …).
