#!/usr/bin/env bash
# host-file <path> [--ephemeral|--permanent] [--name SLUG] [--yes]
#
# Uploads <path> to R2 bucket `tmp` and prints the public URL on stdout.
# All status/errors go to stderr. See SKILL.md for details.

set -euo pipefail

MAX_BYTES=$((200 * 1024 * 1024))

usage() {
  sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'
}

# -- args ------------------------------------------------------------------
TIER=permanent
NAME=""
YES=0
SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ephemeral)  TIER=ephemeral; shift ;;
    --permanent)  TIER=permanent; shift ;;
    --name)
      if [[ -z "${2:-}" ]]; then echo "host-file: --name requires a value" >&2; exit 2; fi
      NAME=$2; shift 2 ;;
    --yes|-y)     YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    --)           shift; SRC="${1:-}"; break ;;
    -*)           echo "host-file: unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)            if [[ -z $SRC ]]; then SRC=$1; shift; else echo "host-file: extra arg: $1" >&2; exit 2; fi ;;
  esac
done

# -- config ----------------------------------------------------------------
CFG="${HOST_FILE_CONFIG:-$HOME/.config/host-file/config.env}"
if [[ ! -f $CFG ]]; then
  echo "host-file: missing config at $CFG" >&2
  echo "host-file: run setup first: bash ~/.claude/skills/host-file/setup-rclone.sh" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$CFG"
: "${R2_REMOTE:?host-file: missing R2_REMOTE in $CFG}"
: "${R2_BUCKET:?host-file: missing R2_BUCKET in $CFG}"
: "${R2_PUBLIC_BASE:?host-file: missing R2_PUBLIC_BASE in $CFG}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE%/}"  # trim trailing slash

if [[ -z $SRC ]]; then usage >&2; exit 2; fi
if [[ ! -f $SRC ]]; then echo "host-file: not a regular file: $SRC" >&2; exit 2; fi

# Resolve to absolute path (readlink -f follows symlinks, which is what we want)
if ! ABS=$(readlink -f -- "$SRC" 2>/dev/null); then
  echo "host-file: cannot resolve path: $SRC" >&2; exit 2
fi

# -- size check ------------------------------------------------------------
SIZE=$(stat -c%s -- "$ABS" 2>/dev/null || stat -f%z -- "$ABS")  # linux | bsd
if (( SIZE > MAX_BYTES )); then
  echo "host-file: file is $((SIZE / 1024 / 1024)) MB, max 200 MB" >&2
  exit 2
fi

# -- blocklist (sensitive paths refuse unconditionally) --------------------
# Match on absolute path. Patterns must be conservative — these are the
# hard rules; we'd rather refuse a benign file than upload a secret.
ABS_LOWER="${ABS,,}"
case "$ABS_LOWER" in
  */.env|*/.env.*|*/.envrc)
    echo "host-file: refusing — .env-like file: $ABS" >&2; exit 3 ;;
  */.ssh/*)
    echo "host-file: refusing — .ssh/ path: $ABS" >&2; exit 3 ;;
  */secrets/*)
    echo "host-file: refusing — secrets/ path: $ABS" >&2; exit 3 ;;
  *credentials*)
    echo "host-file: refusing — 'credentials' in path: $ABS" >&2; exit 3 ;;
  *.age|*.key|*.pem)
    echo "host-file: refusing — key/cert extension: $ABS" >&2; exit 3 ;;
  */id_rsa|*/id_rsa.pub|*/id_ed25519|*/id_ed25519.pub|*/id_ecdsa|*/id_ecdsa.pub)
    echo "host-file: refusing — SSH private/public key: $ABS" >&2; exit 3 ;;
  */fnox.toml|*/fnox.local.toml)
    echo "host-file: refusing — fnox config: $ABS" >&2; exit 3 ;;
esac

# -- compute object key ----------------------------------------------------
BASENAME=$(basename -- "$ABS")
NAMECORE="${BASENAME%.*}"
EXT="${BASENAME##*.}"
# If no extension (basename has no dot), EXT == BASENAME — clear it.
if [[ "$EXT" == "$BASENAME" ]]; then EXT=bin; fi
EXT="${EXT,,}"   # lowercase ext

slugify() {
  # kebab-case: lowercase, replace non-alnum runs with single dash, trim dashes.
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9' '-' \
    | sed -E 's/-+/-/g; s/^-//; s/-$//'
}
SLUG=$(slugify "${NAME:-$NAMECORE}")
[[ -n $SLUG ]] || SLUG=file

# Repo from `git remote get-url origin` in cwd.
OWNER="" REPO=""
if REMOTE=$(git remote get-url origin 2>/dev/null); then
  # Patterns we care about:
  #   git@github.com:owner/repo(.git)
  #   ssh://git@github.com/owner/repo(.git)
  #   https://github.com/owner/repo(.git)
  # And gitlab.com / bitbucket.org / self-hosted with the same shape.
  STRIPPED="${REMOTE%.git}"
  if [[ $STRIPPED =~ ^[^@]+@[^:]+:([^/]+)/(.+)$ ]]; then
    OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"
  elif [[ $STRIPPED =~ ^(ssh|git|https?)://[^/]+(/[^/]+)?/([^/]+)/(.+)$ ]]; then
    OWNER="${BASH_REMATCH[3]}"; REPO="${BASH_REMATCH[4]}"
  fi
fi

YYYY=$(date +%Y)
MM=$(date +%m)
SHORTSHA=$(sha256sum -- "$ABS" | awk '{ print substr($1, 1, 8) }')

if [[ -n $OWNER && -n $REPO ]]; then
  KEY="$TIER/$OWNER/$REPO/$YYYY/$MM/$SHORTSHA-$SLUG.$EXT"
else
  KEY="$TIER/_orphan/${USER:-anon}/$YYYY/$MM/$SHORTSHA-$SLUG.$EXT"
fi

URL="$R2_PUBLIC_BASE/$KEY"

# -- confirmation: only when source is outside cwd -------------------------
CWD=$(pwd -P)
if [[ "$ABS" != "$CWD/"* && "$ABS" != "$CWD" ]]; then
  if (( YES == 0 )) && [[ -t 0 ]]; then
    {
      echo "host-file: source is outside cwd."
      echo "  src: $ABS"
      echo "  dst: $URL"
      printf "Proceed? [y/N] "
    } >&2
    read -r ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "host-file: aborted" >&2; exit 1 ;;
    esac
  fi
fi

# -- upload ----------------------------------------------------------------
echo "host-file: uploading $ABS → $R2_REMOTE:$R2_BUCKET/$KEY" >&2
if ! rclone copyto --s3-no-check-bucket -- "$ABS" "$R2_REMOTE:$R2_BUCKET/$KEY" >&2; then
  echo "host-file: rclone upload failed" >&2
  exit 4
fi

# -- output ----------------------------------------------------------------
echo "$URL"
