---
name: demo-video
description: Produce a narrated, dead-frame-free demo video of a UI flow for a PR, release note, or feature announcement. Use when a frontend PR needs its visual-verification video, when the user asks for a demo / walkthrough recording of an app flow, or when a raw screen capture needs its dead gaps cut and narration + subtitles added.
---

# demo-video

Turn a UI flow into a short narrated video a human actually watches: record in **beats**, cut the dead frames, narrate each beat, burn subtitles, embed in the PR. A beat is one story step a viewer must see (search finds the duplicates → drawer shows the evidence → merge collapses them); everything between beats is dead frames waiting to be cut.

## 1 — Record

- Storyboard the beats first, and seed **real-shaped data** that tells the story — a real duplicate cluster beats a synthetic `[e2e] fixture A` every time.
- Drive with `playwright-cli`: `video-start out.webm --size <W>x<H>` — size to the smallest frame that shows the app's FULL layout (screenshot-check for clipping first; 1280×720 is the sharpness floor, not a default — dense multi-column apps may need 1440×810+). Without `--size` the capture fits 800×800 and text goes soft. Never use `video-chapter` on a final take — it draws a visible callout box onto the page; bind beats by frames instead (step 2).
- Walk the beats with ~1–2s between gestures. Pacing doesn't matter — the cut fixes it; a botched gesture doesn't matter — it becomes dead frames. Verify each beat landed with a screenshot (absolute `--filename=`) before moving on.
- Done when: every beat is on film and confirmed by its screenshot.

## 2 — Cut

- Find dead frames: `ffmpeg -vf "freezedetect=n=-60dB:d=1.0" -an -f null -` → invert into motion windows; merge windows separated by <1.5s; drop sub-0.3s windows on a fixed cadence (UI heartbeat, cursor blink — not gestures).
- **Timestamps drift from your driving script — bind beats to frames, not to command timing.** Render a labeled contact sheet (tiled `drawtext` frames) of the motion windows and label each beat by what you see.
- Per beat keep the motion, then hold the settled frame (`tpad=stop_mode=clone`) just long enough for its narration + ~1.2s. Extract per-segment, concat lossless (`-c copy`).
- Done when: no beat opens on blank/unloaded UI (map tiles, spinners), and cut length ≈ Σ max(motion, narration + pad).

## 3 — Narrate + subtitle

- One spoken line per beat, in the audience's language, written for the viewer ("กดหมุดเพื่อเปิดแผงรายละเอียด"), not a changelog entry.
- TTS the lines. **Thai → Paxa Labs, voice `nomyen` (Nom Yen, female lead)**: `POST https://api.paxalabs.com/v1/tts`, `Authorization: Bearer $PAXALABS_API_KEY`, body `{"text", "voice": "nomyen", "model": "paxa-tts-flash-v1"}`, response is the MP3 itself. `GET /v1/voices` lists the roster. If the key lives in an interactive-only shell rc, agent shells won't see it — inject it explicitly (e.g. `zsh -ic '…'` or your secrets manager's exec wrapper). Other languages → ElevenLabs (a key without `voices_read` can't list voices, so pass a known voice ID). Sanity-check every clip by duration: a 10-second line rendering 70s has looped.
- Trim edge silence + `loudnorm` each line; place at beat offsets with `adelay` + `amix=normalize=0`; every hold ≥ its narration + 1s.
- Build the SRT from the same lines (split >72-char lines at a mid space, time proportional to length). Burn subtitles **last**, after every overlay, with a language-capable font (`force_style='FontName=Noto Sans Thai,...'`).
- **No `subtitles`/`drawtext` filter?** Homebrew's default `ffmpeg` on the Mac is built without libass/freetype (`ffmpeg -filters | grep -E 'subtitles|drawtext'` comes back empty), and Pillow there has no raqm, so it misplaces Thai vowel/tone marks. Instead, render each caption as a transparent PNG in the browser, which shapes Thai correctly (`playwright-cli run-code` → `page.setContent(...)` + element `screenshot({ omitBackground: true })`), then composite with `overlay=enable='between(t,a,b)'`. The same trick works for contact-sheet labels.
- Done when: narration audible on every beat and captions match it word-for-word.

## 4 — Verify + ship

- Contact-sheet the **rendered output** at every beat boundary plus first/last 2s; fix → re-render → re-check, cap 3 passes, then flag what remains.
- Upload (`host-file`). On **GitHub**, an R2-hosted `<video src>` is stripped by CSP (the reviewer sees an empty box), so embed a subtitled **GIF inline** (`![](…gif)`, camo-proxied, ≈8–12 fps, ~720px wide, ≤10 MB) plus a plain link to the narrated MP4. Add a one-line description of what it shows; keep the raw capture as a secondary link.
- Done when: the PR body shows the GIF and links the narrated MP4.

Deep machinery (EDL format, multi-take selection, grades, animation overlays): the `video-use` skill.
