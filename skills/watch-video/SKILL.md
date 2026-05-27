---
name: watch-video
description: Watch and understand local media that Claude Code cannot read natively — primarily video files (.mp4/.mov/.webm/.mkv/.gif) but also any other format the Read tool rejects. Delegates to the `agy` CLI, which extracts keyframes via ffmpeg and reasons about the visuals; can also produce a per-second timeline. Use whenever a local video path appears in the conversation and the user wants to know what's in it — bug-report screen recordings, downloaded chat attachments, dragged-in .mp4 files, GIFs of UI behaviour, anything the user says "watch this video", "what's in this video", "understand this", "describe this recording", "show me the timeline", or invokes `/watch-video`. Do NOT use for YouTube/online URLs (that's `video-extract`) or for voice notes (that's `transcribe-voice-note`).
---

# watch-video (local files)

Claude Code's Read tool accepts images and PDFs but **not video**. When a local video path lands in the conversation and the user wants the contents understood, hand it to `agy`.

## Quick start

```bash
agy -p "<framing prompt + absolute path to video>"
```

`agy` extracts keyframes with ffmpeg, then reasons over them. Output is plain text. **Never pass `--dangerously-skip-permissions`** — the harness blocks it.

## When to use

- Bug-report screen recordings (e.g. attachments downloaded from chat).
- Any local `.mp4` / `.mov` / `.webm` / `.mkv` / `.gif` the user drops or references by path.
- A media file whose path you have but the Read tool refuses with "cannot read this file type".

## When NOT to use

- YouTube / Vimeo / public URLs → `video-extract`.
- Voice notes (`.ogg` / `.m4a` / audio-only `.mp3`) → `transcribe-voice-note`.
- Anything Claude can already see — PNG, JPG, PDF: use Read directly.

## How to write the prompt

`agy` performs much better with a framed prompt than with "describe this video". Always include:

1. **Absolute path** to the file (relative paths fail — `agy` runs in its own cwd).
2. **What the source is** — e.g. "screen recording from a user on Chrome Android".
3. **What the reporter said** — paste the message that accompanied the video, verbatim and in the original language.
4. **The specific question** — "describe each gesture and how the UI responds", "what error appears at the end", "what's the URL bar showing", "which button does the user tap last".

### Template

```
Analyze this <video-type>: <absolute-path>

Context: <one line about source — who sent it, on what device, in what channel>
Reporter said: "<quote the message that came with the video, in original language>"

Describe in detail:
- <specific thing 1 — e.g. the UI being interacted with>
- <specific thing 2 — e.g. each gesture attempted and the UI's response>
- <specific thing 3 — e.g. visible labels, timestamps, error states>

Be concrete about what fails vs. what works.
```

### Example

```bash
agy -p "Analyze this screen recording: /home/me/Downloads/bug-recording.mp4

Context: from a user on Chrome Android, reporting a UI bug in our admin dashboard.
Reporter said: '<exact message the user sent, verbatim>'

Describe in detail:
- the UI being interacted with (which control, which labels visible)
- each gesture attempted and the UI's response
- any dropdown / popover behaviour — does it open, stay, dismiss?
- whether expected behaviour (e.g. scrolling) ever happens

Be specific about what fails."
```

A well-framed call returns a frame-by-frame walkthrough detailed enough to file the bug without re-watching the video.

## Asking for a timeline

`agy` can produce a per-time-mark walkthrough — useful when you need to point at "the gesture at 1.5 s" or correlate the video against logs. It will run `ffmpeg -vf fps=2` (or finer if asked) and return a second-by-second summary.

```
… Produce a TIMELINE: list each second-mark (0.0s, 0.5s, 1.0s, …) and what is
visible at that moment. Extract dense frames (every ~0.5 s or finer) so short
gestures aren't lost. Return as a markdown table with columns:
t (seconds), frame description, gesture, UI state.
```

Tighter intervals (e.g. `fps=4`) help when gestures are < 300 ms — ask for them explicitly.

## Output handling

- Default timeout is 5 minutes; for long videos pass `--print-timeout 10m`.
- If `agy` can't reach the file ("file not found in workspace"), `cd` to a parent directory first or add it: `agy --add-dir <parent> -p "..."`.

## Gotchas

- **Don't paraphrase the reporter's message in the prompt** — quote it verbatim in the original language. The agent uses it to disambiguate which gesture/element is "this one".
- **Audio is ignored.** For screen recordings with narration, also run `transcribe-voice-note` on the same file.
- **One video per call.** Don't batch — each video should get its own framed prompt.
