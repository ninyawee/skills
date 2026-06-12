---
name: host-file
description: Upload a local file to Cloudflare R2 (bucket `tmp`) and print a public URL on stdout. Use when the user wants to attach an image / video / log to a GitHub issue or PR, get a shareable URL for a screenshot, share a debug capture in Discord/Slack, or generate a hosted link for any local file. Triggers on "host this file", "upload to r2", "give me a url for", "share this screenshot", "attach this to issue / PR", or whenever a markdown body needs an image and only a local path is available. Replaces the older "commit screenshots to `docs/screenshots/`" workaround.
---

# host-file

Uploads a local file to Cloudflare R2 bucket `tmp` and prints a single public URL to stdout. Built on `rclone` with an S3-compatible R2 remote.

## Quick usage

```bash
host-file <path>                       # default tier: permanent (never expires)
host-file <path> --ephemeral           # uploads under ephemeral/ — deleted after 30 days
host-file <path> --name custom-slug    # override the slug portion of the URL
```

Output: one line to stdout — the public URL. Status/progress/errors go to stderr.

```bash
$ host-file ./Screenshot-login-bug.png
https://pub-abc123.r2.dev/permanent/ninyawee/pakjai/2026/05/a1b2c3d4-screenshot-login-bug.png
```

## When to reach for it (and when not to)

| Situation | Use this? |
|---|---|
| Image/video needed inside a GitHub issue or PR body | **Yes** |
| Sharing a screenshot in Discord / Slack / chat | Yes |
| Quick public link for a `.log` / `.har` / `.json` to share | Yes |
| Asset that's part of the product (user-facing media, docs site image) | **No** — commit to the repo |
| Anything containing secrets, credentials, `.env`, SSH keys | **No** — blocked by the skill |

## Object key shape

```
<tier>/<owner>/<repo>/<yyyy>/<mm>/<shortsha>-<slug>.<ext>      # in a git repo
<tier>/_orphan/<user>/<yyyy>/<mm>/<shortsha>-<slug>.<ext>      # outside any repo
```

- `tier` — `permanent` (default, never expires) or `ephemeral` (deleted after 30 days). Set via `--ephemeral` / `--permanent`.
- `owner` / `repo` — parsed from `git remote get-url origin` in cwd. Recognises `github.com`, `gitlab.com`, `bitbucket.org`, and `ssh://`/`https://` forms.
- `shortsha` — first 8 hex chars of SHA-256 of the file bytes. Identical re-uploads dedupe to the same URL.
- `slug` — kebab-case of the basename (or of `--name SLUG` if given).

## Safety guarantees

1. **Hard blocklist** — refuses unconditionally if the path matches any of:
   `.env*`, `.envrc`, `.ssh/**`, `secrets/**`, `credentials*`, `*.age`, `*.key`, `*.pem`, `id_rsa*`, `id_ed25519*`, `fnox.toml`, `fnox.local.toml`.
   Blocklist applies *before* any other check. Cannot be bypassed by flags.

2. **Confirmation prompt when source is outside cwd.** If the file path doesn't start with `$(pwd -P)`, prints the intended destination URL and asks `y/N` before uploading. Skipped only when stdin is not a TTY (e.g. piped from a script), in which case the upload proceeds — agents should bear this in mind and pass `--yes` only when intent is explicit.

3. **Max size: 200 MB.** Refuses larger files.

4. **No automatic ingestion** — the skill never reads `~/Pictures/Screenshots/`, the clipboard, or `~/.claude/image-cache/` on its own. The caller must pass an explicit path.

## Examples

```bash
# Embed a screenshot in a GitHub issue
URL=$(host-file ./bug-repro.png --name "login-error-mobile")
gh issue comment 1234 -R ninyawee/pakjai --body "Repro:

![login error]($URL)"

# Ephemeral debug capture — fine for a chat link, will 404 after 30 days
host-file /tmp/regression.mp4 --ephemeral

# Outside cwd — will prompt for y/N
host-file ~/Pictures/Screenshots/Screenshot\ from\ 2026-05-27\ 18-32-19.png
```

## Setup (one-time per machine)

```bash
bash ~/.claude/skills/host-file/setup-rclone.sh
```

The setup script walks you through:

1. R2 bucket public access toggle (manual step in the dashboard).
2. Object lifecycle rule for `ephemeral/` (manual step in the dashboard).
3. R2 API token scoped to bucket `tmp`.
4. `rclone config` for the `r2-tmp` remote.
5. Symlink `host-file` → `~/.local/bin/host-file`.

See `SETUP.md` for the manual steps in detail.

## Implementation

- Wrapper script: `~/.claude/skills/host-file/host-file.sh` (bash, executable).
- Credentials: `~/.config/rclone/rclone.conf` under remote name `r2-tmp` (managed by `rclone config`).
- Config: `~/.config/host-file/config.env` with `R2_REMOTE`, `R2_BUCKET`, `R2_PUBLIC_BASE` (chmod 600).
- Upload primitive: `rclone copyto <local> r2-tmp:tmp/<key> --s3-no-check-bucket`.

## Related skills

- `gh-issue` — older `image` subcommand commits screenshots to `docs/screenshots/` in the target repo. Still available; `host-file` is the less-intrusive alternative for transient artifacts.
