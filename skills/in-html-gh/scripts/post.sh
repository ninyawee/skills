#!/usr/bin/env bash
# post.sh — publish a local HTML viz on a GitHub issue or PR.
#
# The posted body is layered so every reader gets something legible:
#   1. an `x-html` fenced block      → renders inline for reviewers with the gh-x-html extension
#   2. a full-HTML link (R2)         → standalone rendered page for everyone else (host-file)
#   3. a <details> markdown block    → collapsed plain-markdown fallback (always legible)
#
# Three target modes:
#   comment       (default) post as a NEW comment.
#   body-append   append below the existing issue/PR body.
#   body-replace  overwrite the existing issue/PR body. Destructive — confirms if a tty.
#
# Output: stdout = URL of the resulting comment or issue/PR. stderr = status / errors.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: post.sh <html-file> <gh-ref> [options]

  <html-file>   Path to the .html file to embed (with a dark-mode toggle; see SKILL.md).

  <gh-ref>      One of:
                  https://github.com/<owner>/<repo>/issues/<N>
                  https://github.com/<owner>/<repo>/pull/<N>
                  <owner>/<repo>#<N>          (default: issue; append ":pr" to force PR)
                  <owner>/<repo>#<N>:pr
                  <N> or #<N>                 (uses current git remote's owner/repo; issue)
                  #<N>:pr                     (same, PR)

Options:
  --mode <m>            comment | body-append | body-replace      (default: comment)
  --intro <md-file>     Prepend this markdown above the viz (e.g. context blurb).
  --intro-text "..."    Same but inline string instead of a file.
  --md <md-file>        Plain-markdown rendition for the <details> fallback.
                        (default: auto-detect a sibling <html-basename>.md next to the HTML)
  --host-tier <t>       permanent | ephemeral | none   (default: permanent)
                        Hosts the full HTML on R2 (host-file) and adds a click-through link.
                        `none` skips hosting (no link); `ephemeral` auto-expires in 30 days.
  --yes                 Skip the body-replace confirmation prompt.

Examples:
  post.sh ./matrix.html https://github.com/ninyawee/pakjai/issues/932
  post.sh ./viz.html ninyawee/pakjai#932 --mode body-append --intro-text "## Live viz"
  post.sh ./viz.html '#932' --md ./viz.md --host-tier ephemeral
EOF
}

if [[ $# -lt 2 ]]; then usage >&2; exit 1; fi

HTML="$1"; shift
REF="$1"; shift
MODE="comment"
INTRO_FILE=""
INTRO_TEXT=""
MD_ARG=""
HOST_TIER="permanent"
ASSUME_YES="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)        MODE="$2"; shift 2;;
    --intro)       INTRO_FILE="$2"; shift 2;;
    --intro-text)  INTRO_TEXT="$2"; shift 2;;
    --md)          MD_ARG="$2"; shift 2;;
    --host-tier)   HOST_TIER="$2"; shift 2;;
    --yes|-y)      ASSUME_YES="yes"; shift;;
    -h|--help)     usage; exit 0;;
    *)             echo "post.sh: unknown arg: $1" >&2; usage >&2; exit 1;;
  esac
done

case "$MODE" in
  comment|body-append|body-replace) ;;
  *) echo "post.sh: --mode must be comment | body-append | body-replace (got: $MODE)" >&2; exit 1;;
esac
case "$HOST_TIER" in
  permanent|ephemeral|none) ;;
  *) echo "post.sh: --host-tier must be permanent | ephemeral | none (got: $HOST_TIER)" >&2; exit 1;;
esac

[[ -r "$HTML" ]] || { echo "post.sh: cannot read HTML file: $HTML" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "post.sh: 'gh' CLI not found on PATH" >&2; exit 1; }

# ── Parse the ref into OWNER / REPO / NUM / KIND ──────────────────────────────
OWNER=""; REPO=""; NUM=""; KIND="issue"

case "$REF" in
  https://github.com/*/issues/*)
    rest="${REF#https://github.com/}"
    OWNER="${rest%%/*}"; rest="${rest#*/}"
    REPO="${rest%%/*}";  NUM="${rest##*/}"; NUM="${NUM%%[#?/]*}"
    KIND="issue"
    ;;
  https://github.com/*/pull/*)
    rest="${REF#https://github.com/}"
    OWNER="${rest%%/*}"; rest="${rest#*/}"
    REPO="${rest%%/*}";  NUM="${rest##*/}"; NUM="${NUM%%[#?/]*}"
    KIND="pr"
    ;;
  */*\#*:pr)
    base="${REF%:pr}"
    OWNER="${base%%/*}"; rest="${base#*/}"
    REPO="${rest%%#*}";  NUM="${rest#*#}"
    KIND="pr"
    ;;
  */*\#*)
    OWNER="${REF%%/*}";  rest="${REF#*/}"
    REPO="${rest%%#*}";  NUM="${rest#*#}"
    KIND="issue"
    ;;
  \#*:pr|[0-9]*:pr)
    raw="${REF%:pr}"; NUM="${raw#\#}"; KIND="pr"
    ;;
  \#*|[0-9]*)
    NUM="${REF#\#}"; KIND="issue"
    ;;
  *)
    echo "post.sh: cannot parse ref: $REF" >&2; usage >&2; exit 1;;
esac

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  origin="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$origin" ]]; then
    echo "post.sh: ref '$REF' has no owner/repo, and no git origin to infer from." >&2
    exit 1
  fi
  or="$(echo "$origin" | sed -E 's#(git@github\.com:|https?://github\.com/)##; s#\.git$##')"
  OWNER="${or%%/*}"
  REPO="${or##*/}"
fi

[[ -n "$OWNER" && -n "$REPO" && -n "$NUM" ]] || {
  echo "post.sh: incomplete ref (owner=$OWNER repo=$REPO num=$NUM)" >&2; exit 1
}

# ── Fence-collision guard ─────────────────────────────────────────────────────
# Only the HTML matters here — it lives inside the x-html fence. The <details>
# markdown block is outside the fence, so its own code fences are fine.
if grep -F -q '```' "$HTML"; then
  cat <<EOF >&2
post.sh: HTML contains a triple-backtick which would close the x-html fence prematurely.
        Either escape it (HTML entities inside <code>: &#96;&#96;&#96;) or split into smaller files.
        Offending lines:
EOF
  grep -n -F '```' "$HTML" >&2 | head -5
  exit 1
fi

# ── Resolve the markdown fallback (--md, else sibling <name>.md) ───────────────
MD_FILE=""
if [[ -n "$MD_ARG" ]]; then
  [[ -r "$MD_ARG" ]] || { echo "post.sh: cannot read --md file: $MD_ARG" >&2; exit 1; }
  MD_FILE="$MD_ARG"
elif [[ -r "${HTML%.*}.md" ]]; then
  MD_FILE="${HTML%.*}.md"
  echo "post.sh: using sibling markdown fallback ${MD_FILE}" >&2
fi

# ── Host the full HTML on R2 for a click-through link (host-file) ──────────────
HOST_URL=""
if [[ "$HOST_TIER" != "none" ]]; then
  if command -v host-file >/dev/null 2>&1; then
    slug="$(basename "$HTML")"; slug="${slug%.*}"
    tier_flag=()
    [[ "$HOST_TIER" == "ephemeral" ]] && tier_flag=(--ephemeral)
    if HOST_URL="$(host-file "$HTML" --name "$slug" "${tier_flag[@]}" --yes 2>/dev/null)"; then
      echo "post.sh: hosted full HTML ($HOST_TIER) → $HOST_URL" >&2
    else
      echo "post.sh: host-file failed; posting without the full-HTML link." >&2
      HOST_URL=""
    fi
  else
    echo "post.sh: host-file not on PATH; posting without the full-HTML link (set up the host-file skill, or pass --host-tier none)." >&2
  fi
fi

# ── Build reusable parts ──────────────────────────────────────────────────────
INTRO_PART="$(mktemp -t in-html-gh-intro.XXXXXX.md)"
DETAILS_PART="$(mktemp -t in-html-gh-details.XXXXXX.md)"
ADDENDUM="$(mktemp -t in-html-gh-add.XXXXXX.md)"
ADDENDUM_LEAN="$(mktemp -t in-html-gh-lean.XXXXXX.md)"
trap 'rm -f "$INTRO_PART" "$DETAILS_PART" "$ADDENDUM" "$ADDENDUM_LEAN" "${EXISTING:-}" "${COMBINED:-}"' EXIT

if [[ -n "$INTRO_FILE" ]]; then
  [[ -r "$INTRO_FILE" ]] || { echo "post.sh: cannot read intro file: $INTRO_FILE" >&2; exit 1; }
  cat "$INTRO_FILE" >> "$INTRO_PART"; echo "" >> "$INTRO_PART"
fi
if [[ -n "$INTRO_TEXT" ]]; then
  printf '%s\n\n' "$INTRO_TEXT" >> "$INTRO_PART"
fi

if [[ -n "$MD_FILE" ]]; then
  {
    echo '<details>'
    echo '<summary>Details</summary>'
    echo ''
    cat "$MD_FILE"
    echo ''
    echo '</details>'
  } >> "$DETAILS_PART"
fi

# build_addendum <out> <include_fence:yes|no>
build_addendum() {
  local out="$1" include_fence="$2"
  : > "$out"
  [[ -s "$INTRO_PART" ]] && cat "$INTRO_PART" >> "$out"
  if [[ "$include_fence" == "yes" ]]; then
    { echo '```x-html'; cat "$HTML"; echo ''; echo '```'; } >> "$out"
  fi
  if [[ -n "$HOST_URL" ]]; then
    printf '\n📄 **[Open the full rendered page](%s)** — standalone HTML, works without the gh-x-html extension.\n' "$HOST_URL" >> "$out"
  fi
  if [[ -s "$DETAILS_PART" ]]; then
    printf '\n' >> "$out"; cat "$DETAILS_PART" >> "$out"
  fi
}

build_addendum "$ADDENDUM" yes
build_addendum "$ADDENDUM_LEAN" no

# ── Size handling: drop the inline fence (keep link + details) if over limit ──
LIMIT=65536

# pick_addendum <base_existing_bytes> → echoes the chosen addendum path, or fails
pick_addendum() {
  local base="${1:-0}" full_sz lean_sz
  full_sz=$(( base + $(wc -c < "$ADDENDUM") ))
  if (( full_sz <= LIMIT )); then echo "$ADDENDUM"; return 0; fi
  if [[ -n "$HOST_URL" ]]; then
    lean_sz=$(( base + $(wc -c < "$ADDENDUM_LEAN") ))
    if (( lean_sz <= LIMIT )); then
      echo "post.sh: inline x-html block too big ($full_sz > $LIMIT) — dropping it; reviewers use the full-HTML link + Details fallback." >&2
      echo "$ADDENDUM_LEAN"; return 0
    fi
  fi
  cat <<EOF >&2
post.sh: assembled body is too large (${full_sz} bytes > ${LIMIT}) even after fallbacks.
        Split the HTML into smaller artifacts (post as separate comments), trim the markdown
        fallback, or shrink the viz. The full-HTML link offloads rendering but the inline
        fence + <details> still count toward GitHub's per-body limit.
EOF
  return 1
}

# ── Per-mode dispatch ─────────────────────────────────────────────────────────
case "$MODE" in
  comment)
    BODY="$(pick_addendum 0)"
    SIZE=$(wc -c < "$BODY")
    printf 'post.sh: comment on %s/%s#%s (%s, %d bytes)\n' "$OWNER" "$REPO" "$NUM" "$KIND" "$SIZE" >&2
    if [[ "$KIND" == "pr" ]]; then
      gh pr comment    "$NUM" --repo "$OWNER/$REPO" --body-file "$BODY"
    else
      gh issue comment "$NUM" --repo "$OWNER/$REPO" --body-file "$BODY"
    fi
    ;;
  body-append|body-replace)
    EXISTING="$(mktemp -t in-html-gh-existing.XXXXXX.md)"
    if [[ "$KIND" == "pr" ]]; then
      gh pr view    "$NUM" --repo "$OWNER/$REPO" --json body --jq .body > "$EXISTING"
    else
      gh issue view "$NUM" --repo "$OWNER/$REPO" --json body --jq .body > "$EXISTING"
    fi
    OLD_SIZE=$(wc -c < "$EXISTING")

    if [[ "$MODE" == "body-append" ]]; then
      BODY="$(pick_addendum "$(( OLD_SIZE + 2 ))")"
    else
      BODY="$(pick_addendum 0)"
    fi

    COMBINED="$(mktemp -t in-html-gh-combined.XXXXXX.md)"
    if [[ "$MODE" == "body-append" ]]; then
      cat "$EXISTING" >> "$COMBINED"
      printf '\n\n' >> "$COMBINED"
      cat "$BODY" >> "$COMBINED"
    else
      cat "$BODY" >> "$COMBINED"
    fi
    NEW_SIZE=$(wc -c < "$COMBINED")

    if [[ "$MODE" == "body-replace" && "$ASSUME_YES" != "yes" ]]; then
      printf 'post.sh: about to REPLACE the body of %s/%s#%s (was %d bytes, will be %d).\n' \
        "$OWNER" "$REPO" "$NUM" "$OLD_SIZE" "$NEW_SIZE" >&2
      if [[ -t 0 ]]; then
        printf '         Proceed? [y/N] ' >&2
        read -r ans
        case "$ans" in [Yy]*) ;; *) echo "aborted." >&2; exit 1;; esac
      else
        echo "post.sh: stdin is not a tty; pass --yes to confirm destructive body-replace." >&2
        exit 1
      fi
    fi

    printf 'post.sh: %s body of %s/%s#%s (%s, %d → %d bytes)\n' \
      "$MODE" "$OWNER" "$REPO" "$NUM" "$KIND" "$OLD_SIZE" "$NEW_SIZE" >&2

    if [[ "$KIND" == "pr" ]]; then
      gh pr edit    "$NUM" --repo "$OWNER/$REPO" --body-file "$COMBINED" >/dev/null
      gh pr view    "$NUM" --repo "$OWNER/$REPO" --json url --jq .url
    else
      gh issue edit "$NUM" --repo "$OWNER/$REPO" --body-file "$COMBINED" >/dev/null
      gh issue view "$NUM" --repo "$OWNER/$REPO" --json url --jq .url
    fi
    ;;
esac
