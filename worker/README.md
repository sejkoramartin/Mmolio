# Optional Mmolio worker and displays

**English** · [Čeština](README-CS.md)

This component is separate from Garmin Bluetooth sharing. It receives
Nightscout-compatible uploads from xDrip4iOS, stores the latest reading in KV and
serves a web display and JSON API. Wrangler is a development dependency invoked
through `npx wrangler`. No worker deployment is needed for the watch installers.

```text
xDrip4iOS → POST /api/v1/entries → your worker → /api/glucose → displays
```

## Setup

Follow the [installation guide](../docs/INSTALL.md) to create your own KV namespace,
Secrets Store secret and ignored `wrangler.local.toml`. Existing deployment commands:

```bash
npm install
npx wrangler login
npx wrangler kv namespace create TOKEN_KV
npx wrangler secrets-store store create mmolio
npx wrangler secrets-store secret create <STORE_ID>   --name NIGHTSCOUT_API_SECRET --scopes workers --remote
cp wrangler.toml wrangler.local.toml
# Enter your KV and store IDs in wrangler.local.toml.
npx wrangler deploy -c wrangler.local.toml
```

The secret is entered interactively. Use at least 12 characters and keep it out of
source control. Include bindings in the configuration file; do not rely on
dashboard-only bindings being preserved by deployment.

In xDrip **Settings → Nightscout**, enter your worker URL, the API_SECRET and enable
uploads. **Test connection** uses `/api/v1/experiments/test`.

## Operations

```bash
# Development with remote bindings:
npx wrangler dev --remote -c wrangler.local.toml
# Deploy your configured worker:
npx wrangler deploy -c wrangler.local.toml
# Read the latest available value:
curl -s https://glykemie.YOUR-NAME.workers.dev/api/glucose
```

No usable reading returns HTTP 503. Uploads follow source measurements rather than
being polled by the worker. Data age must remain visible. The read endpoint is
public to anyone who knows its URL; see the [disclaimer](../docs/DISCLAIMER.md).

## Web display

Open the worker URL in Safari and use **Share → Add to Home Screen** for a dedicated
phone display. Auto-Lock and Guided Access can be configured in iOS. Avoid a bright
static display on OLED devices; the existing interface uses a dark design.

The web display uses range colours configured in `colorForValue()` in
`public/index.html` (existing limits: 4.2–9.5 mmol/L). It does not inherit the
Garmin unit preference.

[Historical maintainer context (Czech)](CLAUDE.md) and
[handover notes (Czech)](HANDOVER.md) are retained separately from this user guide.
