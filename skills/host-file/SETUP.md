# host-file — one-time setup

The R2 bucket itself is already prepared (public access on, lifecycle rule
for `ephemeral/` 30-day expiry in place) — applied via the Cloudflare API
during initial skill creation. The only remaining step is creating a
scoped API token, then wiring it into rclone.

Run the automated walker:

```bash
bash ~/.claude/skills/host-file/setup-rclone.sh
```

…or do it by hand using the steps below.

## 1. Create a scoped R2 API token (dashboard only)

The dashboard is the only place that exposes the S3-style `Access Key ID` and
`Secret Access Key` — they're not returned by the generic `POST /accounts/{id}/tokens`
endpoint, only by the dashboard's "Create R2 API Token" flow.

Go to <https://dash.cloudflare.com/&lt;account-id&gt;/r2/api-tokens> (your account
ID is the 32-hex string in any R2 dashboard URL) → **Create API Token**:

| Field | Value |
|---|---|
| Token name | `host-file` |
| Permission | **Object Read & Write** |
| Specify buckets | **Apply to specific buckets only** → `tmp` |
| TTL | Forever (or your call) |

After creation, Cloudflare shows the **Access Key ID** and **Secret Access Key**
once — copy both before navigating away.

## 2. Configure `rclone` and `host-file`

```bash
rclone config create r2-tmp s3 \
  provider Cloudflare \
  access_key_id "$R2_ACCESS_KEY_ID" \
  secret_access_key "$R2_SECRET_ACCESS_KEY" \
  endpoint "https://<account-id>.r2.cloudflarestorage.com" \
  acl private

mkdir -p ~/.config/host-file
cat > ~/.config/host-file/config.env <<EOF
R2_REMOTE=r2-tmp
R2_BUCKET=tmp
R2_PUBLIC_BASE=https://pub-XXXXXXXX.r2.dev
EOF
chmod 600 ~/.config/host-file/config.env

chmod +x ~/.claude/skills/host-file/host-file.sh
ln -sf ~/.claude/skills/host-file/host-file.sh ~/.local/bin/host-file
```

## 3. Verify

```bash
# rclone can list the bucket?
rclone lsd r2-tmp:

# end-to-end (uploads to ephemeral/, auto-deletes in 30d):
echo hello > /tmp/host-file-smoke.txt
host-file /tmp/host-file-smoke.txt --ephemeral --name smoke-test --yes
# → https://pub-XXXXXXXX.r2.dev/ephemeral/_orphan/<user>/2026/05/...-smoke-test.txt

# verify the URL works:
curl -sSf "$(host-file /tmp/host-file-smoke.txt --ephemeral --name smoke-test --yes)" | head
```

## What's already configured on the bucket

These were applied via the Cloudflare API during skill creation and don't
need to be re-done unless you delete and recreate the bucket:

- **Public r2.dev access** — `enabled: true`, hostname `pub-XXXXXXXX.r2.dev`. Verify: `GET /accounts/<id>/r2/buckets/tmp/domains/managed`.
- **Lifecycle rule `ephemeral-30d`** — prefix `ephemeral/`, delete objects after 30 days. Coexists with the default multipart-abort rule. Verify: `GET /accounts/<id>/r2/buckets/tmp/lifecycle`.

To re-apply (e.g. after recreating the bucket), the original MCP calls were:

```js
// Enable public access
cloudflare.request({
  method: "PUT",
  path: `/accounts/${accountId}/r2/buckets/tmp/domains/managed`,
  body: { enabled: true },
});

// Set lifecycle rules
cloudflare.request({
  method: "PUT",
  path: `/accounts/${accountId}/r2/buckets/tmp/lifecycle`,
  body: {
    rules: [
      { id: "Default Multipart Abort Rule", enabled: true,
        conditions: { prefix: "" },
        abortMultipartUploadsTransition: { condition: { type: "Age", maxAge: 604800 } } },
      { id: "ephemeral-30d", enabled: true,
        conditions: { prefix: "ephemeral/" },
        deleteObjectsTransition: { condition: { type: "Age", maxAge: 2592000 } } },
    ],
  },
});
```

## Notes

- Account ID is supplied at setup time — `setup-rclone.sh` prompts for it (or reads `R2_ACCOUNT_ID` from the env) and derives the rclone endpoint URL from it. Nothing personal is committed in the skill.
- The token's secret lives in `~/.config/rclone/rclone.conf` (mode 600). Don't commit it.
- `R2_PUBLIC_BASE` lives in `~/.config/host-file/config.env` (mode 600) — strictly speaking it's the public URL, not a secret, but keeping it out of any committed file is the easy default.
- If you rotate the API token, re-run `setup-rclone.sh` and pick the same remote name (`r2-tmp`) — it overwrites cleanly.
