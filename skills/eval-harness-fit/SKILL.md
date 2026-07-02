---
name: eval-harness-fit
description: Audit your CLAUDE.md + rules against the CURRENT harness — judge each directive keep/cut/tighten/relocate/merge for staleness, harness-redundancy, over-constraint, and misplacement. Report-only HTML viz; never writes to the audited files.
disable-model-invocation: true
---

# /eval-harness-fit

Decide whether each instruction in your CLAUDE.md files (and, with `--global`, `~/.claude/CLAUDE.md` + `rules/`) still **earns its place** now that the Claude Code harness keeps improving. The fear this answers: rules that have become *noise* (the harness already does it), *wrong* (the world moved on), or that make Claude *dumber* (over-constrain judgment).

This is a **review**, report-only. For the *apply* flow — prune-and-refresh that edits files directly and mines session transcripts for missing guidance — use **`/maintain-claude-md`**. `/eval-harness-fit` is the harness-aware, evidence-first lens that `/maintain-claude-md` lacks; don't duplicate its session-analysis or its direct edits here.

## Run modes (parse from `$ARGUMENTS`)

| Arg | Effect |
|---|---|
| *(none)* | Audit the instruction payload **active in this session**: loaded global `~/.claude/CLAUDE.md` + path-`rules/` **and** the current repo's CLAUDE.md tree (root + nested). Mark each as always-on vs on-demand. |
| `<path>` | Narrow to one file or dir (e.g. `/eval-harness-fit ~/.claude` for just the global layer, or `/eval-harness-fit supabase/CLAUDE.md`). |
| `--global` | Force-include the global `~/.claude` layer even when run inside a repo. |
| `--deep` | Add the expensive checks: empirical A/B on doubtful rules, and `gh issue view <N>` status for referenced issues/PRs/ADRs. Off by default (slow, network). |
| `--md` | Emit a markdown report instead of the HTML viz (for piping / pasting a fix straight into a file). |

## The oracle — how "does the harness already do this?" is decided

The auditing agent **is running under the very harness it's judging**, so the primary probe is introspection, backed by cross-reference. Per finding, in order:

1. **Introspect** — *"If this line weren't here, would I do it anyway, because the harness already makes me?"* If yes → redundant-with-harness.
2. **Cross-reference** the rest of the payload — other CLAUDE.md files (root ↔ area) and memory (`~/.claude/projects/*/memory/`). Contradictions and duplication surface here, not from self-reasoning.
3. **Verify references exist** — every file / path / `mise` task / skill / command / env var a directive names must resolve (`ls`/`glob`/`grep`). A named-but-missing reference is dead.
4. **Docs cross-check** — for any capability you're unsure is now built-in (the model's training cutoff may lag the harness), confirm via the `claude-code-guide` agent or docs **before** declaring it redundant. Never cut on a guess about a built-in.

Known harness defaults you should NOT restate (non-exhaustive): minimal comments, no over-engineering, no defensive handling of impossible cases, validate only at boundaries, prefer parallel tool calls, prefer dedicated tools over bash, terse output, git-safety (no push/commit unless asked), security/OWASP basics.

## Verdict taxonomy (per directive)

**action** {keep · cut · tighten · relocate · merge} + **reason** {`stale-or-wrong` · `redundant-with-harness` · `redundant-with-tooling/code` · `duplicate` · `misplaced` · `too-vague/tutorial` · `over-constraining`} + **evidence** (cite the file:line / harness-default / counterexample) + **confidence** (0–1).

`relocate` names a target:
- **→ hook** — a deterministic always/never a script can enforce for free, every time, without spending context (formatting, "run X after editing Y", "never touch generated file Z"). Propose the `settings.json` stub.
- **→ path-rule** (`~/.claude/rules/<lang>/<name>.md` with `paths:` frontmatter) — a directive that only matters for a file type but sits always-on. Propose the rule file + frontmatter.
- **→ skill** — a multi-step procedure with a clear trigger, not a standing constraint.
- **project↔global** — a directive living in the wrong layer.

## Workflow

### 1. Discover
Resolve scope (above). List the target files; for each, read it and note `last_audited` frontmatter (if any) and `git log -1 --format=%cr -- <file>` age. Break each file into atomic **directives** (a bullet or sentence) — judge at this grain, never whole-section.

### 2. Judge — STALENESS FIRST (the headline class)
Stale-or-wrong is the highest severity: a redundant line wastes tokens, a stale line gives *wrong* instructions. For every directive run the cheap checks:
- **Reference existence** (oracle §3).
- **Intra-payload contradiction** (oracle §2) — e.g. an area file saying "tenant_id being removed, in-flight" while root says "dropped, complete" → area file is stale.
- **Recency** — `last_audited`/git age is old *and* the world it describes moved (an "in-flight #N" since closed; a "being removed" that's done). With `--deep`, confirm via `gh issue view <N> --json state`.

Then the remaining reasons via the oracle: redundant-with-harness, redundant-with-tooling/code, duplicate, misplaced, too-vague/tutorial.

### 3. Counterexample-test the over-constraining ones (the "makes-dumber" class)
This verdict is the easiest to get wrong, so it requires evidence, not a vibe. For each directive that smells like it replaces judgment with a blanket rule, try to construct 2–3 concrete scenarios where following it *literally* yields a worse outcome than using judgment:
- **Found a plausible counterexample** → it over-reaches. Verdict `tighten` (add the missing scope/escape-hatch, e.g. "*for CREATE TABLE migrations,* …") or `cut`. Cite the counterexample.
- **Can't construct one** → load-bearing. Keep. Do not flag terse-but-correct rules just for being absolute.

With `--deep`, escalate genuinely doubtful rules to an empirical A/B (run a representative task with and without the directive; compare).

### 4. Emit — report only, never write
Produce the output (below). **Do not edit any audited file and do not touch `last_audited`** — nothing was applied. The user applies by hand, asks you to "apply rows 3, 7, 9," or runs `/maintain-claude-md` for the direct-edit flow.

## Output

Default: a self-contained **HTML viz** via `/in-html` viz-mode patterns (Pico CSS via CDN, saved to `/tmp/in-html/eval-harness-fit-<scope>.html`, opened in the browser):

- **Budget banner** — N directives → keep/cut/tighten/relocate/merge counts + estimated always-on tokens reclaimable.
- **Stale-or-wrong callout** up top (highest severity), each with its failing check.
- **Per-file section** → a per-directive table sorted **stale-first, then confidence desc**: directive (quoted) · action · reason · evidence · confidence · **paste-ready fix** (the condensed replacement text, the hook/path-rule stub, or "delete").

`--md` emits the same content as markdown instead. (To share a *project's* audit on a PR, hand the HTML to the `in-html-gh` skill to post it as an `x-html` comment.)

## Guardrails
- **Report-only.** Never writes to the audited files; never updates `last_audited`.
- **Cite or it didn't happen.** Every `cut`/`tighten`/`stale` verdict names the harness default, the contradicting file:line, the dead reference, or the counterexample. No vague "this might be redundant."
- **Don't cut on a cutoff guess.** If unsure whether something is now a built-in, check docs first (oracle §4).
- **Staleness outranks elegance.** Lead with what's *wrong*, not what's merely verbose.
