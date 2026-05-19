---
name: wrap-up
description: "End-of-session handover: make the work durable enough that a future contributor (or future-you on a different machine) can pick it up from PRs + issues + the repo alone — no chat transcript, no local plan file, no `/tmp` extraction. Use when the user says 'wrap up', 'stop here', 'pause for later', 'handover', 'save context', 'before I go', or 'leave it tidy'."
---

# Wrap-up Skill

End a work session by making **everything load-bearing live in a durable, discoverable place** — a PR description, a PR comment, a GitHub issue, or a file in the repo. The test: a teammate who never read this chat and is on a different machine can pick up the work from those artifacts alone.

The two failure modes this skill prevents:
1. **"It's in my plan file"** — local-only files (`~/.claude/plans/`, `/tmp/extracted/`, scratch notes) don't survive across machines or sessions.
2. **"You had to be there"** — decisions captured only in chat transcripts evaporate. New people can't see what was ruled out or why.

## When to use

The user is wrapping up for the day, week, or indefinitely. Trigger phrases include "wrap up", "stop here", "pause for later", "handover", "save context", "before I go", "leave it tidy", or after they say something like "we'll continue tomorrow / next week / when X happens".

Distinct from `/bump` (releases) or `/commit` (single commit). This skill is for **handoff readiness**, not version cuts.

## The wrap-up grand picture

A complete wrap-up answers three questions for the next reader:

1. **What got built** — pointer to PRs/branches/issues, status of each
2. **What's left** — pointer to next steps with enough detail to start
3. **What surprised us** — decisions made, dead-ends found, things that aren't obvious from the diff

Every answer must land somewhere with a URL. Local files don't count.

## Workflow

### Step 1 — Inventory the session

Run these in parallel:

```bash
# 1a. Branches + PRs touched
git branch --show-current
git log --oneline origin/HEAD..HEAD          # commits ahead of remote
gh pr list --author '@me' --state open --limit 10
gh issue list --search "<feature name>" --state all --limit 20

# 1b. Uncommitted / running state to address before leaving
git status -s
ps aux | grep -E "vite|dev3000|next|bun.*dev" | grep -v grep
ss -ltn | grep -E ":5[0-9]{3}"                # dev servers still bound
```

Note: `git status -s` will surface auto-format noise from tools like d3k. Mark those as "non-ours, will be left alone or discarded" rather than committing them.

### Step 2 — Probe durability

For each artifact created in the session, ask: **can a stranger find it without my chat or my machine?** Walk through these candidates and check each:

| Artifact | Durable enough? |
|---|---|
| GitHub PR body / comment | ✅ yes |
| GitHub issue with label | ✅ yes |
| File committed to a pushed branch | ✅ yes |
| File at `~/.claude/plans/*.md` | ❌ no — local only |
| Files under `/tmp/` | ❌ no — ephemeral |
| Decisions in chat transcript | ❌ no — invisible to new readers |
| External URL the user shared (design files, dashboards) | ⚠️ only if mirrored — capture the URL in the repo or an issue |

If any load-bearing context is in a ❌ row, **move it** before continuing.

### Step 3 — Persist the context (the durable triad)

For non-trivial work (anything beyond a single small PR), set up three artifacts that cross-reference each other:

#### 3a. In-repo spec doc — `docs/specs/<feature>.md`

This is the source-of-truth. Includes:

- TL;DR of the feature + why now (link to design/wireframe URL if applicable)
- Stack layout / scope table — what's done, what's open, what's next
- **Resume here** block — rebase commands, prerequisites, local-state hacks (if any)
- Per-PR detailed scope for unstarted work — schema, frontend, API, verification each
- **Decisions captured during grilling** — one row per call: question / decision / rationale
- Out-of-scope follow-ups
- Pre-merge checklist

Commit on the umbrella/mother branch so it flows into the integration PR. If no umbrella branch exists, commit on the lead feature branch.

For stacked PRs, this doc belongs on the **mother branch** — adding a commit there doesn't disturb the child PR diffs (children rebase onto updated mother at merge time anyway).

#### 3b. GitHub issue with `spec` label (or similar)

Mirror the doc as an issue body. The issue is for discussion + tracking; the file is the canonical source.

Create the label if it doesn't exist:

```bash
gh label create spec --description "Specification / feature design document" --color BFD4F2 --force
```

When creating the issue body, lead with:
> Source of truth lives in the repo at `docs/specs/<feature>.md` on the `<branch>` branch. This issue mirrors that doc for tracking + discussion. If they diverge, the file is canonical.

#### 3c. PR descriptions + status comments

For each open PR in the stack:

- **Body** — ensure the description covers: what shipped, schema/API/frontend breakdown, verification done, known gaps. If the original body is thin, expand it via `gh pr edit <n> --body "$(cat <<'EOF' …)"`.
- **Status comment** — post one comment per PR with:
  - Position in the stack (parent + children)
  - "Develop drift" warning if base branch has moved (count commits with `git rev-list --count origin/develop ^HEAD`)
  - Rebase command sequence the merger will need
  - Pointer to the spec issue / doc
  - Known gaps deferred to downstream PRs

### Step 4 — Cross-link everything

Bidirectional links are non-negotiable. Verify each:

- Spec doc → links to mother PR + child PRs + spec issue
- Spec issue → links to mother PR + child PRs + repo doc (canonical-source notice)
- Mother PR → links to spec issue + lists each child PR with status
- Each child PR → links to spec issue + names parent + child in the stack
- README / project tracker (if any) → links to spec issue

### Step 5 — Tidy local state

- **Kill dev servers**: `pkill -9 -f "vite|dev3000|bun.*dev"`. Verify ports freed: `ss -ltn | grep ":51[0-9]{3}"`.
- **Note (don't commit) auto-format noise** in `git status -s`. Surface to the user: "these aren't ours; safe to `git checkout --` next time."
- **Stash drop or keep**: if there are session-WIP stashes, list them and tell the user. Don't drop without permission.

### Step 6 — Update task list

If a `TaskCreate`/`TaskUpdate` task list was used, leave it in the right state:

- Completed tasks → `completed`
- In-progress tasks → either complete them, or move back to `pending` with the partial work captured in the spec doc
- Pending tasks for next session → keep `pending` with clear `description` text that points to the spec

### Step 7 — Final report to the user

A single message summarizing the **grand picture**. Pattern:

```
Stack/work state:
  develop
    └─ feat/X (#553 mother, draft)
         ├─ feat/X-01-… (#554, ready for review)
         └─ feat/X-02-… (#555, ready for review)

Spec: #573 (and docs/specs/X.md on feat/X)

Done this session:
  - <bullet> · <bullet> · <bullet>

Not yet started (each has full scope in spec):
  - PR3 (…) · PR4 (…) · PR5 (…)

Drift / re-entry notes:
  - origin/develop is ~N commits ahead of stack base — rebase before PR3
  - GEMINI_API_KEY needed in your local secrets file
  - <other one-line gotchas>

Local cleanup: dev server stopped · 2 auto-format files left unstaged (not ours)
```

Keep it tight. The reader will click into PRs/issues for detail.

## Confidence checklist — before declaring wrap-up complete

Walk through each, fix anything that's no:

- [ ] Every load-bearing artifact has a URL (PR / issue / repo file at a pushed commit)
- [ ] Spec doc + issue + PRs all cross-link bidirectionally
- [ ] Resume instructions are concrete enough that a stranger can execute them without asking (exact commands, no hand-waving)
- [ ] Develop drift surfaced if non-trivial
- [ ] Local processes stopped, ports freed
- [ ] Task list reflects reality
- [ ] Final report names PR/issue numbers, not just descriptions

## When not to use this skill

- The user is mid-task and just pausing for 10 minutes (no handover risk)
- A single trivial commit on `main` with no follow-up
- The user explicitly says "don't bother with docs, just commit and push"

In those cases, skip to a minimal "stopping here" message and let them go.
