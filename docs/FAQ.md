# Frequently asked questions

**English** · [Čeština](FAQ-CS.md)

## General

### Does Mmolio replace my sensor app or alarms?

No. It displays readings already measured by your sensor. Keep your usual alarms
enabled and read the [disclaimer](DISCLAIMER.md).

### Do I need xDrip4iOS?

The supplied Garmin receiver uses a compatible xDrip4iOS Garmin sender. The optional
worker can accept Nightscout-compatible uploads from other sources.

### Which watches are covered?

Release candidates are built for `fr165`, `fenix7xpro` and `fenix7xpronowifi`.
Physical validation of the current candidate is pending. Other models need their
own build and validation; do not infer compatibility from similar names.

### Where do my readings go?

For Garmin, from your phone to the selected watch via Garmin's SDK. The optional
web/desktop route uses your own Cloudflare worker. Its read endpoint is public to
anyone who knows the URL; do not publish that URL with your glucose data.

## Garmin

### Where do I download the watch applications?

Use the model-specific ZIP under [release Assets](https://github.com/sejkoramartin/Mmolio/releases)
and follow the [installation guide](GARMIN-INSTALL.md). GitHub's Source code archives
are for developers, not watch installation. No Connect IQ Store listing is claimed.

### How do I change mmol/L to mg/dL?

With Mmolio rc2 or later and the updated sender, use the existing unit preference
in xDrip. Bridge, WatchFace and active DataField follow it automatically. Offline
changes wait for reconnection. Older senders without unit metadata use each
receiver's local preference; update both sides and allow a new reading to arrive.

### The watch shows NO DATA

Open Bridge once after installation and check Garmin sharing in xDrip. DataField
has its own application ID and needs a sender that sends directly to it. It must
be active in an activity to receive. NO DATA is expected before the first valid reading.

### Bridge has a reading, but WatchFace does not

Install Bridge and WatchFace from the same release and open Bridge once. They
must share a signing key for the private complication to be readable.

### What do STALE and CHECK TIME mean?

STALE means the measurement is too old (default 15 minutes). The display turns
grey and hides the trend arrow. CHECK TIME means the measurement time is in the
future relative to the watch. Check device clocks. Receipt time never replaces
measurement time.

### Why does raising my wrist not wake the screen?

Wake behaviour is controlled by the watch firmware and gesture/sleep settings.
Mmolio does not control the firmware's display wake policy.

### Why is the AMOLED always-on ring incomplete?

The low-power design uses a moving segment and shifts the content. The full ring
appears when awake. MIP Fenix targets use a different low-power layout policy.

### Can I change colours or glucose limits?

Range limits are configured in Bridge for the face, and separately in DataField.
Their local threshold settings use mmol/L. Automatic phone units control display
formatting, not those threshold settings. Colours are implemented in
`MmolioWatchFace/source/xDripWatchFaceView.mc` and `MmolioDataField/source/FieldRenderer.mc`.

### The build cannot find a device definition

Use Connect IQ SDK 9.2.0 and install the exact target's device definitions in SDK
Manager. Device definitions are downloaded separately from the SDK archive.

## Optional worker and desktop components

### /api/glucose returns 503

No usable reading is available. Check data age, xDrip's worker URL, API_SECRET,
upload setting and **Test connection**.

### xDrip's connection test fails

Check the full `https://` URL, secret and deployed worker. The existing setup
instructions use a secret of at least 12 characters and no trailing URL slash.

### Uploads stop after deployment

Check KV and secret bindings in `wrangler.local.toml`. The project's deployment
configuration must include them rather than relying only on dashboard settings.

### A secret's .get() call fails

The worker's historical troubleshooting notes identify an outdated
`compatibility_date` as a cause. Preserve the repository's configured date and
Secrets Store binding type when reproducing that setup.

### My GNOME code changes do not appear

After changing `extension.js`, log out and in on Wayland. `config.json` changes
are read at runtime. Inspect extension errors with:

```bash
gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell   --method org.gnome.Shell.Extensions.GetExtensionErrors "glykemie@sejkora.local"
```

### How do I silence the desktop alarm?

Use the extension's **Alarm** switch. It stops the current overlay/sound and
persists the choice; the value display and panel notifications remain separate.

## Development

### Can I check changes without watches?

```bash
.github/scripts/garmin-checks.sh
./garmin/scripts/build-fr165.sh --test
# With the SDK simulator running:
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioBridge.prg fr165 -t
```

See the [technical guide](../garmin/README.md) for all three applications. Simulator
tests cannot validate real Bluetooth delivery or iPhone background behaviour.

### Why do some internal names still say MedProbe or xDripWatchFace?

They are historical names. Keeping application IDs and compatible internal
contracts avoids breaking existing senders and installations.

### Why is the iPhone app named xDrip4iO5?

That naming comes from the xDrip project and is separate from Mmolio.
