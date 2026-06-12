#!/usr/bin/env bash
# Interactive one-time setup for the `host-file` skill.
#
# - Walks the user through the manual Cloudflare R2 dashboard steps
# - Captures R2 API credentials interactively (no secret on argv)
# - Configures an `r2-tmp` rclone remote
# - Writes ~/.config/host-file/config.env (chmod 600)
# - Symlinks ~/.local/bin/host-file -> ~/.claude/skills/host-file/host-file.sh
# - Runs a smoke test if requested

set -euo pipefail

# Your Cloudflare R2 details. Pre-fill via env (R2_ACCOUNT_ID=... ./setup-rclone.sh)
# or you'll be prompted. Nothing personal is hardcoded here.
R2_ACCOUNT_ID="${R2_ACCOUNT_ID:-}"
R2_REMOTE=r2-tmp
R2_BUCKET=tmp
# Bucket-specific public URL (pub-XXXX.r2.dev), shown in the R2 dashboard once
# public access is enabled. Pre-fill via R2_PUBLIC_BASE_DEFAULT or be prompted.
R2_PUBLIC_BASE_DEFAULT="${R2_PUBLIC_BASE_DEFAULT:-}"

CFG_DIR="$HOME/.config/host-file"
CFG="$CFG_DIR/config.env"
SCRIPT_PATH="$HOME/.claude/skills/host-file/host-file.sh"
LINK_PATH="$HOME/.local/bin/host-file"

# --- dependency checks ----------------------------------------------------
command -v rclone >/dev/null || { echo "rclone not found on PATH — install it first" >&2; exit 2; }
command -v sha256sum >/dev/null || { echo "sha256sum not found on PATH" >&2; exit 2; }

# --- resolve account-derived URLs ----------------------------------------
if [[ -z "$R2_ACCOUNT_ID" ]]; then
  read -r -p "Cloudflare account ID (32 hex chars, from the R2 dashboard URL): " R2_ACCOUNT_ID
fi
[[ -n "$R2_ACCOUNT_ID" ]] || { echo "account ID is required" >&2; exit 2; }
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
DASHBOARD_URL="https://dash.cloudflare.com/${R2_ACCOUNT_ID}/r2/default/buckets/${R2_BUCKET}"
TOKENS_URL="https://dash.cloudflare.com/${R2_ACCOUNT_ID}/r2/api-tokens"

cat <<EOF
=== host-file setup ===

This will configure rclone + host-file for the R2 bucket "$R2_BUCKET".

Public access and the ephemeral/ 30-day lifecycle rule are already configured
on this bucket (applied via the Cloudflare API). The only remaining manual
step is creating a scoped API token — those S3-style credentials cannot be
retrieved through the generic tokens API, so the dashboard is the only path.

In the Cloudflare dashboard:

  Create a scoped R2 API token
     - Open: $TOKENS_URL
     - "Create API Token"
       · Token name:  host-file
       · Permission:  Object Read & Write
       · Buckets:     "Apply to specific buckets only" → $R2_BUCKET
       · TTL:         "Forever" (or your preference)
     - Copy the "Access Key ID" and "Secret Access Key" — shown only once.

EOF

read -r -p "Have you created the token? [y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "OK — come back when ready."; exit 0 ;;
esac

# --- collect inputs -------------------------------------------------------
if [[ -n "$R2_PUBLIC_BASE_DEFAULT" ]]; then
  read -r -p "Public R2.dev base URL [$R2_PUBLIC_BASE_DEFAULT]: " R2_PUBLIC_BASE
else
  read -r -p "Public R2.dev base URL (https://pub-XXXXXXXX.r2.dev): " R2_PUBLIC_BASE
fi
R2_PUBLIC_BASE="${R2_PUBLIC_BASE:-$R2_PUBLIC_BASE_DEFAULT}"
R2_PUBLIC_BASE="${R2_PUBLIC_BASE%/}"
[[ -n "$R2_PUBLIC_BASE" ]] || { echo "public base URL is required" >&2; exit 2; }
if [[ ! $R2_PUBLIC_BASE =~ ^https://pub-[a-z0-9]+\.r2\.dev$ ]]; then
  echo "warning: that doesn't look like a pub-XXXXXXXX.r2.dev URL — continuing anyway" >&2
fi

read -r -p "R2 Access Key ID: " R2_ACCESS_KEY_ID
read -r -s -p "R2 Secret Access Key (hidden): " R2_SECRET_ACCESS_KEY
echo

# --- configure rclone remote ---------------------------------------------
# `rclone config create` is non-interactive and idempotent (it overwrites).
echo "writing rclone remote '$R2_REMOTE' to ~/.config/rclone/rclone.conf" >&2
rclone config create "$R2_REMOTE" s3 \
  provider Cloudflare \
  access_key_id "$R2_ACCESS_KEY_ID" \
  secret_access_key "$R2_SECRET_ACCESS_KEY" \
  endpoint "$R2_ENDPOINT" \
  acl private \
  >/dev/null

# --- write host-file config ----------------------------------------------
mkdir -p "$CFG_DIR"
umask_old=$(umask)
umask 077
cat > "$CFG" <<EOF
# host-file config — generated $(date -u +%FT%TZ)
# Edit by hand if any of these change. Secrets live in rclone.conf, not here.
R2_REMOTE=$R2_REMOTE
R2_BUCKET=$R2_BUCKET
R2_PUBLIC_BASE=$R2_PUBLIC_BASE
EOF
umask "$umask_old"
chmod 600 "$CFG"
echo "wrote $CFG" >&2

# --- symlink to ~/.local/bin ---------------------------------------------
chmod +x "$SCRIPT_PATH"
mkdir -p "$(dirname "$LINK_PATH")"
ln -sf "$SCRIPT_PATH" "$LINK_PATH"
echo "symlinked $LINK_PATH → $SCRIPT_PATH" >&2

# --- smoke test (optional) -----------------------------------------------
read -r -p "Run a smoke test (uploads /tmp/host-file-smoke.txt then deletes it)? [y/N] " ans
if [[ $ans =~ ^[yY] ]]; then
  TEST_FILE=/tmp/host-file-smoke.txt
  echo "host-file smoke test $(date -u +%FT%TZ)" > "$TEST_FILE"
  if URL=$("$SCRIPT_PATH" "$TEST_FILE" --ephemeral --name "smoke-test" --yes); then
    echo
    echo "✓ smoke test uploaded to: $URL"
    echo "  (auto-deletes in 30 days; lives under ephemeral/)"
  else
    echo "✗ smoke test failed — check rclone config and try: rclone lsd $R2_REMOTE:" >&2
    rm -f "$TEST_FILE"
    exit 4
  fi
  rm -f "$TEST_FILE"
fi

cat <<EOF

✓ host-file setup complete.

Try it:
  echo hello > /tmp/hello.txt
  host-file /tmp/hello.txt --ephemeral

Make sure \$HOME/.local/bin is on \$PATH if 'host-file' isn't found.
EOF
