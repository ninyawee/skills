---
description: Merge a GitHub PR safely with full pre-merge checks AND post-merge deploy verification. Use when the user says "merge PR", "merge this PR", "merge to main", "ship this", or invokes /merge-pr. Critical: a green PR check does NOT mean the post-merge deploy succeeds — different workflows can run different build paths. This skill enforces watching the post-merge Deploy run and hotfixing immediately if it fails, instead of leaving main broken.
---

Merge a PR safely. `$ARGUMENTS` — optional PR number; if omitted, infer from the current branch (`gh pr list --head $(git branch --show-current)`). If still unclear, ask once.

Merging is not "click button, done." The PR check workflow and the post-merge Deploy workflow are usually separate, and they can run different build paths — a PR can be green and merging it can break main. This skill is the end-to-end discipline that closes that gap.

The promise to the user when they say "merge this": their fix is **live on prod** (or whatever the deploy target is). Not "the PR is green" — that was already true when they asked. They want the change visible to actual users. So the skill isn't done until the post-merge deploy is verified.

## 1. Pre-merge double-check

One call:

```bash
gh pr view <N> --repo <owner>/<repo> \
  --json baseRefName,headRefName,state,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,isDraft,title,additions,deletions,changedFiles
```

Verify and surface:

- **Base branch matches the user's intent.** A `fix/...` branch targeting `develop` when they said "merge to main" is a red flag — confirm before proceeding.
- **`mergeable: MERGEABLE`** and **`mergeStateStatus: CLEAN`**. `UNSTABLE` is OK only if you can identify the failing checks as non-required and you call them out explicitly.
- **Not a draft.** If it is, mark it ready first (or stop and ask).
- **All required checks SUCCESS.** SKIPPED is fine for path-filtered workflows that don't apply to the diff. FAILURE on a required check is a stop.
- **`reviewDecision`.** If the project requires approval and there isn't one, stop and tell the user — don't try to bypass.
- **Diff size matches expectations.** A "small fix" PR with 80 changed files is a smell — surface it before merging.

## 2. Pick the merge method by project convention

Don't impose a personal preference — match what the project already does:

```bash
git log origin/<base-branch> --oneline --merges -5
```

- "Merge pull request #..." commits → `--merge`
- Linear history with PR-titled commits → `--squash`
- Linear history with no merge commits → `--rebase`

If unclear, ask once. Don't guess a method that rewrites history.

## 3. Do the merge

```bash
gh pr merge <N> --repo <owner>/<repo> --<method> --delete-branch
```

`gh pr merge` returns no output on success — silence is success, not failure. Confirm with git, not with the absence of an error:

```bash
git fetch origin <base-branch>
git log origin/<base-branch> --oneline -3
```

You should see the new merge/squash/rebase commit at HEAD.

**Auto-mode classifier note:** the harness sometimes blocks follow-up `gh pr view`/`gh pr merge` calls touching the default branch. If `gh pr merge` returned no output but a follow-up command was blocked, the merge most likely went through — verify with `git fetch && git log origin/<base-branch> --oneline -3` before re-trying. Re-issuing the merge against an already-merged PR will error.

## 4. Post-merge verification — the part this skill exists for

**PR checks ≠ deploy success.** The PR's CI workflow (often "Check") is usually different from the post-merge "Deploy" workflow. They can run different build paths, hit different environments, or use different flags. A green PR check is not evidence the deploy will succeed.

Concrete failure mode this skill exists to prevent: a changelog bullet contained a literal `<` (e.g. `font-size < 16px`). The PR's "Check" workflow built the app and passed. The post-merge "Deploy" workflow ran the prod build, the Markdown/MDX parser interpreted `<` as the start of an HTML tag, and the deploy died with a tag-parse error. Main was broken until a hotfix PR landed. The PR appeared "merged" for several minutes before anyone realized prod hadn't actually moved.

After the merge, find the new Deploy run on the target branch:

```bash
gh run list --repo <owner>/<repo> --branch <base-branch> --workflow=Deploy --limit 2 \
  --json databaseId,status,conclusion,createdAt,headSha,event
```

Match by `headSha` to the merge commit. Then watch it in the background (so you don't burn cache while it polls):

```bash
gh run watch <databaseId> --repo <owner>/<repo> --exit-status
```

Use `run_in_background: true` — you'll be notified when it finishes.

If the project also has separate post-merge workflows (e.g. `Sync develop with main`, migrations, container image builds), watch each one that's relevant to the diff. A green Deploy with a failing Sync is still a partial outcome worth flagging — but it's a separate cleanup, not a blocker on the merge being "done."

## 5. If the post-merge deploy fails — incident mode

Treat this as an incident: main is broken, fix it now, don't move on to the next thing.

1. Get the failure log:
   ```bash
   gh run view <run-id> --repo <owner>/<repo> --log-failed | tail -80
   ```
2. **Diagnose, don't guess.** Reproduce locally with the exact command the workflow runs (often `bun run build` / `npm run build` from the relevant subdirectory with the prod env vars set). The PR build passed — something differs in the deploy build, find it.
3. Open a hotfix PR from a fresh branch off main. Smallest possible diff — fix the root cause, nothing else.
4. **Bump the patch version for the affected area.** A hotfix to main is a real shipment that bypasses the normal develop→main `/release` flow, so the version bump that flow would have done has to happen inline. For each `package.json` (or equivalent manifest) in the affected area, increment the patch number, and roll the relevant `## next` / `## [Unreleased]` section of the changelog file into a new `## vX.Y.Z — <date>` section with the hotfix bullet at the top. Skipping this leaves prod at the same version string as the broken release — staff can't tell from the version whether they're on the broken or fixed build, and the staged section keeps growing across hotfixes until someone untangles it. If the project has a `/bump patch` skill, use it. Otherwise do it by hand and follow the existing version-section format in the changelog file. Commit the bump alongside the fix in the same hotfix PR.
5. **Verify the fix locally before pushing.** The deploy build is what failed; reproduce that, not the PR check.
6. Push, wait for PR checks, merge with the same discipline (back to step 1), watch the next Deploy run.
7. Only after the second Deploy goes green is the original "merge" actually done.

## 6. Don't announce "fixed" until prod is verified

If the user asked you to also notify someone (Discord, Slack, email, GitHub issue) that the work is done, that notification waits for the post-merge Deploy to go green. A "fix is shipped" message landing while main is broken is worse than no message — the recipient will check and report it as still broken, undermining trust.

If the user explicitly tells you to notify *now* anyway, do it — but tell them prod hasn't deployed yet so they can word the message accordingly.

## 7. Side cases worth knowing

- **Migrations in the diff.** If the diff touches `supabase/migrations/`, the post-merge Deploy probably includes a migration step. Watch that step specifically — a failed migration on prod is much harder to undo than a failed build, and the rollback story is different (often forward-fix only).
- **Required reviewers.** `reviewDecision: REVIEW_REQUIRED` with no approval = stop. Tell the user. Don't bypass.
- **Stacked PRs.** If this PR is part of a stack (gh-stack or graphite), merging it can cascade rebases on dependent PRs. Verify the dependent PRs auto-rebase or surface the manual step.
- **Force-pushed during your session.** Re-fetch and re-check the PR state before merging if any time has passed since the last check — someone may have pushed.
