# skills

My personal Claude Code skills and slash commands.

Everything lives under [`skills/`](./skills/) — each in its own directory with a
`SKILL.md`. Install into `~/.claude/skills/` (or a project's `.claude/skills/`),
or add straight from GitHub with [`skills`](https://skills.sh/):

```sh
skills add ninyawee/skills --skill '*'
```

## Skills

Auto-invokable skills — Claude reaches for these on its own when the task fits,
and you can also call them by name.

| Skill | About |
|---|---|
| [`bbt`](./skills/bbt/) | Black-box testing — make software easy to test, cover a bug with a failing test before fixing it, stub external seams, and generate tests with AI. |
| [`in-html`](./skills/in-html/) | Build one self-contained HTML artifact — either a read-only visualization of an implementation plan, or an editable HITL UI to shape structured data and copy the result back as JSON. |
| [`in-html-gh`](./skills/in-html-gh/) | Build an HTML viz (via `in-html`) and publish it to a GitHub issue/PR — inline `x-html` fence + a full-HTML R2 link + a collapsed `<details>` markdown fallback; generated HTML carries a dark-mode toggle. |
| [`host-file`](./skills/host-file/) | Upload a local file to Cloudflare R2 (bucket `tmp`) and print a public URL — for attaching screenshots/videos/logs to GitHub issues/PRs or sharing in chat. Secret blocklist, 200MB cap, `--ephemeral` (30-day) tier. |
| [`recipe`](./skills/recipe/) | Turn recipe videos / URLs / descriptions into visual step-by-step recipe notes with Gemini-generated step images. |
| [`scrutinize`](./skills/scrutinize/) | Outsider-perspective end-to-end review of a plan, PR, or code change — questions intent first, then traces the real code path to verify the change does what it claims. |
| [`watch-video`](./skills/watch-video/) | Watch and understand local video files (the Read tool can't) by delegating to the `agy` CLI for keyframe analysis and per-second timelines. |
| [`wrap-up`](./skills/wrap-up/) | End-of-session handover — make the work durable enough that a future contributor can pick it up from PRs + issues + the repo alone. |

## Slash-command skills

User-invoked only (`disable-model-invocation: true`) — these behave like the old
slash commands: they run when you type `/<name>`, and Claude never triggers them
on its own. (Converted from the former `commands/`.)

| Skill | About |
|---|---|
| [`commit`](./skills/commit/) | Create a git commit. |
| [`commit-staged`](./skills/commit-staged/) | Commit only staged changes (does not stage anything). |
| [`commit-many`](./skills/commit-many/) | Break changes into multiple logical commits by intent. |
| [`commit-push-pr`](./skills/commit-push-pr/) | Commit, push, and open a PR. |
| [`eval-harness-fit`](./skills/eval-harness-fit/) | Audit your CLAUDE.md + rules against the current harness — judge each directive keep/cut/tighten/relocate/merge for staleness, harness-redundancy, over-constraint, and misplacement. Report-only HTML viz. |
| [`init-claude-review-ci`](./skills/init-claude-review-ci/) | Set up (or repair) the Claude Code Review GitHub Action in the current repo — the validated sticky, single-updating-comment config. |
| [`loose-ends`](./skills/loose-ends/) | Audit the session for unfinished, unverified, or risky work. Reports a prioritized list; fixes nothing unless told to. |
| [`merge-pr`](./skills/merge-pr/) | Merge a GitHub PR safely with full pre-merge checks AND post-merge deploy verification. |
| [`new-wt`](./skills/new-wt/) | Create a new git worktree for a feature/fix, bootstrap it per the project's conventions, and open it in VS Code. |
| [`setup-wt-bootstrap`](./skills/setup-wt-bootstrap/) | Set up a repo so `git worktree add` auto-bootstraps the new worktree (mise `wt:bootstrap` task + a shared `post-checkout` git hook). |

## License

MIT.
