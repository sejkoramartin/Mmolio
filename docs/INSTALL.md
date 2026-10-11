# Installation

**English** · [Čeština](INSTALL-CS.md)

Read the [disclaimer](DISCLAIMER.md) first. Components are independent: install
only the ones you need. **For Garmin, start with the [watch installation guide](GARMIN-INSTALL.md).**
It covers ready-made ZIPs for each supported target; no Cloudflare account, worker
or local compilation is needed for the Garmin route.

```text
sensor → xDrip4iOS → Garmin Bridge / WatchFace / DataField
                  └→ optional Cloudflare Worker → web display
```

## Optional Cloudflare worker

The worker receives Nightscout-compatible uploads, stores the latest reading in
KV, and serves a web display plus `/api/glucose`. This route requires your own
Cloudflare account and Node.js. These are the project's existing deployment steps.

```bash
git clone https://github.com/sejkoramartin/Mmolio.git
cd Mmolio/worker
npm install
npx wrangler login
npx wrangler kv namespace create TOKEN_KV
npx wrangler secrets-store store create mmolio
npx wrangler secrets-store secret create <STORE_ID>   --name NIGHTSCOUT_API_SECRET --scopes workers --remote
cp wrangler.toml wrangler.local.toml
```

Enter the secret interactively and use at least 12 characters. Put your KV and
Secrets Store IDs in `wrangler.local.toml`, which is ignored by Git. Keep secrets
and personal IDs out of the repository.

```bash
npx wrangler deploy -c wrangler.local.toml
```

Keep bindings in the configuration file; do not rely on dashboard-only settings
being preserved by deployment. Save the worker URL printed by Wrangler.

In xDrip4iOS **Settings → Nightscout**, enter the worker URL and your API_SECRET,
enable uploads, then use **Test connection**. The worker implements
`/api/v1/experiments/test` for that check.

```bash
curl -s https://glykemie.YOUR-NAME.workers.dev/api/glucose
# An unauthenticated write should be rejected with HTTP 401:
curl -s -o /dev/null -w "%{http_code}\n" -X POST   https://glykemie.YOUR-NAME.workers.dev/api/v1/entries -d '[]'
```

HTTP 503 means no usable reading is available; check uploads and data age.
**The read endpoint is public to anyone who knows the URL.** See the disclaimer.

## Optional phone or tablet display

1. Open your worker URL in the browser.
2. On iPhone, use **Share → Add to Home Screen**, then launch it from there.
3. For a dedicated display, configure **Settings → Display & Brightness → Auto-Lock**.
4. Guided Access can keep the display app on screen; configure it in iOS settings.

Display colour thresholds are in `colorForValue()` in `worker/public/index.html`.
This optional display is separate from the Garmin unit setting.

## Garmin development

For normal installation, use the [release ZIP guide](GARMIN-INSTALL.md).
For local builds, see the [Garmin technical guide](../garmin/README.md) and
[Fenix targets](FENIX.md). The sender is the separate
[xDrip4iOS Garmin PR](https://github.com/JohanDegraeve/xdripswift/pull/771).
Update both sender and receivers for automatic mmol/L / mg/dL selection.

## Further reading

- [FAQ](FAQ.md)
- [Worker operations](../worker/README.md)
- [Documentation index](README.md)
