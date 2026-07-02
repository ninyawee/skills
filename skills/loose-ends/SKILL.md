---
name: loose-ends
description: Audit this session for loose ends — uncommitted work, unverified deploys, manual steps left to the user, leftover test artifacts, secrets, foot-guns, doc drift. Reports a prioritized list; fixes nothing unless told to.
disable-model-invocation: true
---

Review what was done in **this session** and surface what's unfinished, unverified, or risky. Output one prioritized list — per item, a line of *what* and a line of the concrete *check* or *do* (a command, a query, a UI step). **Don't fix anything** unless the user follows up ("do N" / "fix N"). `$ARGUMENTS` — optional area to scope to; default: everything touched.

Walk these, skipping any that don't apply:

1. **Git working tree** — `git status --short` + `git log --oneline -5`. Flag uncommitted changes *I made*. Changes that appeared but *not by me* (pre-existing edits, a stray formatter/hook, the user editing in parallel): flag separately as "not mine — decide commit vs restore", never stage/revert without asking. Note any commit whose message overclaims vs its diff.
2. **Deployed but not verified** — anything pushed to a live system (a remote write, a deploy, a migration, an API call with side effects) that wasn't *seen working* after. Give the step that would actually confirm it; "returned 2xx" ≠ "works".
3. **Secrets** — did a secret literal land in a committed file or git history this session? If a leaked credential's target resource is now gone (no longer resolves / responds), it's inert — say so; otherwise it needs rotation. If a new credential *binding* was used, is it actually authorized for what it now points at, or just one that made validation pass?
4. **Manual steps left to the user** — anything the agent couldn't do (a permission block, an account/API toggle, an editor-only step, an interactive login, a UI-only action, a value the user must paste). Confirm each is written down somewhere with a ready-to-run command, and restate it here.
5. **Leftover test artifacts** — scratch rows/records, temp files in the repo or `/tmp`, a throwaway branch/worktree, a draft PR. Where it is + how to remove it.
6. **Foot-guns introduced** — a live-only override a re-run would clobber; a stale generated/gitignored file; a destructive task without a dry-run; a hardcoded id that differs across environments. Note it + where it's documented.
7. **Inactive / half-wired** — something created but not activated, deployed but not pointed at, scheduled but disabled. List what's still "off".
8. **Doc drift** — did this session make a README / CLAUDE.md / codemap / notes file describe something wrongly now? Suggest the targeted fix; don't do it.
9. **Waived items** — anything the user explicitly said to skip. List once for the record, then drop.

If there genuinely are none, say so plainly — don't manufacture items. End by offering to act on any of them.
