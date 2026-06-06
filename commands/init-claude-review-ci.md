---
description: Set up (or repair) the Claude Code Review GitHub Action in the current repo using the validated sticky, single-updating-comment config. Use whenever the user wants to "init CI for Claude", add an automated Claude PR reviewer, set up claude-code-action review, or fix a claude-review workflow that runs green but posts no review.
argument-hint: "[target branches, e.g. main  or  develop,main]"
allowed-tools: Bash(gh *), Bash(git *), Bash(ls *), Bash(cat *), Bash(test *), Bash(base64 *), Read, Write, Edit, AskUserQuestion
---

# Init Claude Code Review CI

Scaffold a GitHub Actions workflow that makes Claude review every PR and post its
findings into **one sticky comment that updates in place on each push** (authored
by the Claude GitHub App). This is the configuration that was reverse-engineered
from `anthropics/claude-code-action@v1` source and verified live — follow it
exactly, because the obvious-looking alternatives silently post nothing.

`$ARGUMENTS` (optional) = comma-separated long-lived branches PRs target (e.g.
`main` or `develop,main`). If empty, detect them (step 2).

## Why this exact shape (don't "simplify" it away)

The action has two modes and the difference is everything:

- **Agent mode** = a `prompt:` *without* `track_progress`. It adds **no base
  tools** and treats `claude_args --allowedTools` as the *exclusive* allow-list.
  So passing posting tools there *removes* Claude's own Read/Grep/etc. → it can't
  even read the diff → dozens of permission denials → job goes green, posts
  nothing. This is the #1 failure and it looks like success.
- **Tag mode** = `track_progress: true`. The action posts one tracking comment,
  ships the full base toolset (Read/Grep/LS/git/`update_claude_comment`), and
  writes the review into that comment. `use_sticky_comment: true` makes each push
  reuse the **same** comment (matched by the Claude App's bot author id) instead
  of stacking a new one. In tag mode only `mcp__github_*` tools from
  `claude_args` are honored — which is exactly enough to switch on inline
  comments. **This is the mode we want.**

Also non-obvious:
- Permissions must be **write** (`pull-requests`, `issues`). Read-only ⇒ the
  action withholds its posting tools ⇒ nothing posts.
- Sticky dedup only matches comments authored by the **Claude GitHub App**
  (bot id `209825114`). If the App isn't installed, the GITHUB_TOKEN posts as
  `github-actions[bot]`, which never matches ⇒ comments stack. So the App is a
  hard prerequisite for stickiness, not optional polish.
- The official `code-review` *plugin* posts via `gh pr comment`, which bypasses
  the sticky machinery and always creates a new comment. Don't use the plugin
  for a sticky reviewer — use tag mode with a direct prompt.

## Procedure

### 1. Preflight
- Confirm a git repo with a GitHub remote: `gh repo view --json nameWithOwner,defaultBranchRef -q '{repo:.nameWithOwner, default:.defaultBranchRef.name}'`. If this fails, stop and tell the user to run it inside a GitHub-connected repo (offer `gh repo create` / `git init` only if they ask).
- Note `owner/repo` and the default branch.

### 2. Decide target branches
- If `$ARGUMENTS` is set, use it verbatim (split on commas).
- Else detect: always include the default branch. If a `develop` branch also exists remotely (`git ls-remote --heads origin develop` returns a line), this is a gitflow repo — target **both** `develop` and `main` and add the release-PR skip guard (step 4). Otherwise target just the default branch.
- Briefly tell the user which branches you'll target and why; let them override.

### 3. Check prerequisites (these are the things only the user can do)
Run both checks, then report status before writing anything.

- **`CLAUDE_CODE_OAUTH_TOKEN` secret** — `gh secret list` (and `gh secret list --org <owner>` if it's an org and you have access). If absent, the cleanest fix is the Claude Code built-in: have the user run `claude` then `/install-github-app`, which installs the App **and** sets this secret in one step. Surface that as a `! /install-github-app` suggestion (the `!` runs it in their session). Manual alternative: create a long-lived token with `claude setup-token` and `gh secret set CLAUDE_CODE_OAUTH_TOKEN`.
- **Claude GitHub App installed** — can't be read reliably with a PAT. Check for past evidence: `gh api repos/<owner>/<repo>/issues/comments --paginate -q '.[].user | select(.id==209825114) | .login' | head -1`. If that prints `claude[bot]`, it's installed. If nothing prints, it's *probably* not installed — tell the user to install it via `/install-github-app` or https://github.com/apps/claude , and warn that **without it the review still posts but stacks a new comment per push** (no stickiness).

Don't block on these — you can still write the workflow. Just be explicit about what's missing and what the consequence is.

### 4. Write the workflow
Target path: `.github/workflows/claude-code-review.yml`.

If it already exists, read it and show the user a diff of what you'd change before overwriting (a common reason for running this command is to *repair* a broken existing workflow — preserve any custom prompt the user clearly tuned, but fix mode/permissions/tools).

Use this exact template. Substitute `BRANCHES` with the comma-separated targets from step 2. Include the `if:` skip line **only** for gitflow repos (so develop→main release PRs aren't reviewed):

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]
    # Only review PRs targeting these long-lived branches
    branches: [BRANCHES]

jobs:
  claude-review:
    # GITFLOW-ONLY: skip release/sync PRs between long-lived branches (develop -> main)
    if: github.head_ref != 'develop' && github.head_ref != 'main'

    runs-on: ubuntu-latest
    permissions:
      contents: read
      # write (not read) so the review can be posted back to the PR.
      pull-requests: write
      issues: write
      id-token: write
      # actions: read  # optional — enables Claude's CI-status tools in tag mode

    steps:
      - name: Checkout repository
        uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - name: Run Claude Code Review
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}

          # track_progress -> tag mode: one tracking comment that Claude writes
          # the review into (via the built-in update_claude_comment tool).
          # use_sticky_comment -> reuse the SAME Claude-App-authored comment each
          # push instead of stacking. (Requires the Claude GitHub App installed.)
          track_progress: true
          use_sticky_comment: true

          prompt: |
            Review this pull request as a senior engineer. Prioritize, in order:
            1. Correctness bugs, logic errors, data-loss / security risks
            2. Broken or missing error handling at real boundaries
            3. Clear simplifications, dead code, or duplicated logic

            Put a concise summary in your tracking comment, grouped by severity
            and linking files/lines. Use inline comments for specific line-level
            issues, with a suggested fix where it's obvious. Skip style nits and
            praise. If the PR is solid, say so in a line or two.
            Review only — do not commit, push, or modify any files.

          # In tag mode only mcp__github_* tools from here are honored. This one
          # enables line-level inline comments (the action registers the inline
          # server when this tool is allowed). Inline comments are NOT deduped
          # across pushes — only the summary comment is sticky; GitHub marks
          # superseded inline comments "outdated".
          claude_args: |
            --allowedTools "mcp__github_inline_comment__create_inline_comment"
```

For a non-gitflow repo (single target branch), delete the two `if:` comment+line entirely.

### 5. Commit / open PR
Per git-safety norms, don't push silently. Ask the user how to land it:
- **PR (default):** create a branch `ci/claude-review`, commit just this file, push, open a PR with `gh pr create` summarizing what it does + the App/token prerequisites.
- **Direct commit:** commit straight to the current branch (only if they say so).
- **Write only:** leave it staged for them to handle.

Commit message: `ci: add Claude Code Review (sticky tag-mode reviewer)`. Add the standard Co-Authored-By trailer.

### 6. Tell them how to verify
- The workflow runs on the next PR open/`synchronize` against a target branch (it can't be triggered with `workflow_dispatch`).
- Expect one comment authored by `claude[bot]` (App id `209825114`) containing the review; on the next push that **same** comment updates in place.
- If it runs green but posts nothing: 99% of the time it's read-only permissions, agent mode (missing `track_progress`), or a missing `CLAUDE_CODE_OAUTH_TOKEN`. If it posts but stacks duplicates: the Claude GitHub App isn't installed.

## Output
End with a short summary: which branches it targets, prerequisite status (token ✓/✗, App ✓/✗/unknown), where the file landed (PR link or path), and the single most important next action for the user (usually: install the App, or set the token, or just "open a PR to see it run").
