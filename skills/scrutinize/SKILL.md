---
name: scrutinize
description: Outsider-perspective end-to-end review of a plan, PR, or code change. First questions intent and whether a simpler/more elegant approach would achieve the same goal, then traces the actual code path (not just the diff) to verify the change does what it claims. Output is concise, actionable, and every call carries its rationale. When the artifact is a GitHub PR, also records the outcome on the PR as labels (local-scrutinized + a verdict tag; verdict:ship once findings clear). Trigger on /scrutinize and proactively whenever the user asks to review, audit, sanity-check, or get a second opinion on a plan, PR, diff, design doc, or proposed code change.
---

# Scrutinize

Stand outside the change and ask whether it should exist at all, then verify it actually does what it claims end-to-end.

## Operating stance

- **Outsider.** Forget who wrote it and why they think it's right. Read the artifact cold.
- **End-to-end, not diff-local.** The diff is the entry point, not the scope. Follow the call graph through real code paths.
- **Actionable, concise, with rationale.** Every finding states *what to change*, *why*, and *what evidence* led you there. No filler, no restating the diff back.

## Workflow

Run these in order. Do not skip ahead.

### 1. Intent — what is this actually trying to do?

- State the goal in one sentence, in your own words. If you cannot, the artifact is underspecified — say so and stop.
- Ask: **is there a simpler, smaller, or more elegant way to achieve the same goal?** Consider:
  - Doing nothing (is the problem real / load-bearing?).
  - Using something that already exists in the codebase instead of adding new surface.
  - A smaller change that solves 90% of the goal with 10% of the risk.
  - Solving it at a different layer (config vs code, framework vs app, build vs runtime).
- If a better alternative exists, name it explicitly with rationale. This is the most valuable thing you can output — surface it before the line-by-line review.

### 2. Trace — walk the actual code path

- For each behavior the change claims, trace the path end-to-end through the real code, not just the lines in the diff:
  - Entry point → call sites → branches taken → state mutated → exit / return / side effect.
  - Include the unchanged code on either side of the diff. Bugs hide at the seams.
- For a plan or design doc: trace the proposed flow against the existing system. Where does it touch reality? What does it assume that isn't true?
- Note every place the trace surprises you (unexpected branch, dead code reached, state you didn't know existed). Surprises are signal.

### 3. Verify — does it actually do what it claims?

For each claim the change/plan makes, answer:

- **Does the code path you just traced actually produce that behavior?** Walk it explicitly. "It claims X. Path: A → B → C. At C, [observation]. Therefore [holds / doesn't hold]."
- **What inputs / states would break it?** Edge cases, concurrent callers, error paths, partial failures, retries, empty/null/unicode/huge inputs, ordering assumptions.
- **What does it silently change?** Performance, error semantics, observability, contract for other callers, on-disk / on-wire format.
- **How is it tested?** Do the tests actually exercise the traced path, or do they pass while skipping it (mocks that hide the bug, asserts on intermediate state, happy path only)?

### 4. Report

Output one tight section per finding. Order by severity (blocker → major → nit). For each:

- **Finding** — one sentence, specific. Cite `file:line` when applicable.
- **Why it matters** — the consequence, not the principle.
- **Evidence** — the trace step or input that exposes it.
- **Suggested change** — concrete, minimal.

Close with a one-line verdict: ship / fix-then-ship / rework / reject — with the single biggest reason.

## PR mode — record the verdict as labels

When the artifact under review **is a GitHub PR** (the user pointed `/scrutinize` at a PR number/URL, or you're on a branch with an open PR), record the outcome on the PR after the report so the verdict is visible without reading the comment. Skip this entirely for plans, design docs, or local-only diffs.

Resolve the PR number first: `gh pr view --json number -q .number` for the current branch, or take the number/URL the user gave. Then:

1. **Ensure the label scheme exists** (idempotent — `--force` creates or updates, safe to run every time):

   ```bash
   gh label create local-scrutinized      --color 5319e7 --description "Reviewed locally via /scrutinize" --force
   gh label create "verdict:ship"          --color 0e8a16 --description "Local scrutiny: cleared to merge (clean, or findings fixed)" --force
   gh label create "verdict:fix-then-ship" --color fbca04 --description "Local scrutiny: minor fixes needed before merge" --force
   gh label create "verdict:rework"        --color d93f0b --description "Local scrutiny: needs rework before re-review" --force
   gh label create "verdict:reject"        --color b60205 --description "Local scrutiny: do not merge this approach as-is" --force
   ```

2. **Mark it scrutinized and clear any stale verdict state** (a re-run must not leave a previous verdict behind):

   ```bash
   gh pr edit <N> --add-label local-scrutinized
   gh pr edit <N> --remove-label "verdict:ship" --remove-label "verdict:fix-then-ship" \
                  --remove-label "verdict:rework" --remove-label "verdict:reject" 2>/dev/null || true
   ```

3. **Apply the current verdict tag** — exactly one:

   | Verdict | Label to add |
   |---|---|
   | ship | `verdict:ship` |
   | fix-then-ship | `verdict:fix-then-ship` |
   | rework | `verdict:rework` |
   | reject | `verdict:reject` |

   `gh pr edit <N> --add-label <label-from-table>`

`local-scrutinized` is sticky — it stays once set, marking "a human-driven scrutiny happened here." The verdict tag is the *current* state and is replaced on every re-run. So the intended loop is: first pass lands `local-scrutinized` + e.g. `verdict:fix-then-ship`; the author fixes the findings; a re-scrutiny confirms them resolved and flips the tag to `verdict:ship` (the green "merge it" flag). A clean PR on the first pass goes straight to `verdict:ship`.

This replaces the old CI auto-review (the GitHub Action posted a comment on every push) with a deliberate, human-triggered review whose outcome is a glanceable label rather than comment noise.

## Operating rules

- **No rubber-stamps.** "LGTM" is not an output. If you genuinely find nothing, say what you traced and what you checked, so the user can judge whether your review covered the surface they cared about.
- **Cite or it didn't happen.** Every claim about the code references a specific path, file, or line. No vague "this might break under load."
- **Distinguish claim from verification.** "The PR says X" and "I traced X and confirmed / refuted it" are different — keep them separate in the output.
- **One simpler-alternative pass is mandatory.** Even on small changes, spend one breath asking if the whole thing is necessary. Skip only if the user explicitly says "don't question scope."
- **Don't pad with style nits when there's a structural problem.** If step 1 or step 2 surfaces a real issue, lead with it; defer nits or drop them.
- **No flattery, no hedging.** "This is a great PR but..." adds nothing. State the finding.
