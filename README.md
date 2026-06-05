# skills

My personal Claude Code skills and slash commands.

## Skills

Live under [`skills/`](./skills/) — each in its own directory with a `SKILL.md`.

| Skill | About |
|---|---|
| [`in-html`](./skills/in-html/) | Build one self-contained HTML artifact — either a read-only visualization of an implementation plan, or an editable HITL UI to shape structured data and copy the result back as JSON. |
| [`recipe`](./skills/recipe/) | Turn recipe videos / URLs / descriptions into visual step-by-step recipe notes with Gemini-generated step images. |
| [`watch-video`](./skills/watch-video/) | Watch and understand local video files (the Read tool can't) by delegating to the `agy` CLI for keyframe analysis and per-second timelines. |
| [`wrap-up`](./skills/wrap-up/) | End-of-session handover — make the work durable enough that a future contributor can pick it up from PRs + issues + the repo alone. |

## Commands

Live under [`commands/`](./commands/) — drop into `~/.claude/commands/` (or a project's `.claude/commands/`) to use as slash commands.

| Command | About |
|---|---|
| [`commit`](./commands/commit.md) | Create a git commit. |
| [`commit-staged`](./commands/commit-staged.md) | Commit only what's staged. |
| [`commit-many`](./commands/commit-many.md) | Break changes into multiple logical commits by intent. |
| [`commit-push-pr`](./commands/commit-push-pr.md) | Commit, push, and open a PR. |
| [`eval-harness-fit`](./commands/eval-harness-fit.md) | Audit your CLAUDE.md + rules against the current harness — judge each directive keep/cut/tighten/relocate/merge for staleness, harness-redundancy, over-constraint, and misplacement. Report-only HTML viz. |
| [`loose-ends`](./commands/loose-ends.md) | Audit the session for unfinished, unverified, or risky work. Reports a prioritized list; fixes nothing unless told to. |
| [`merge-pr`](./commands/merge-pr.md) | Merge a GitHub PR safely with full pre-merge checks AND post-merge deploy verification. |
| [`new-wt`](./commands/new-wt.md) | Create a new git worktree for a feature/fix, bootstrap it per the project's conventions, and open it in VS Code. |
| [`setup-wt-bootstrap`](./commands/setup-wt-bootstrap.md) | Set up a repo so `git worktree add` auto-bootstraps the new worktree (mise `wt:bootstrap` task + a shared `post-checkout` git hook). |

## License

MIT.
