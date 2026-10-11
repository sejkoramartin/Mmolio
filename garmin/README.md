# Mmolio for Garmin

**English** · [Čeština](README-CS.md)

**Install on your watch:** [English guide](../docs/GARMIN-INSTALL.md) · [Český návod](../docs/GARMIN-INSTALL-CS.md)

Three applications are built for Forerunner 165 and the `fenix7xpro` /
`fenix7xpronowifi` targets. See [Fenix build and model selection](../docs/FENIX.md).

- **Mmolio Bridge:** phone-message receiver, including background reception.
- **Mmolio WatchFace:** time, date, battery, glucose, trend, measurement age, heart rate and steps.
- **Mmolio DataField:** glucose, trend, units and age during an activity; receives directly from the phone.

Current release candidates have build and simulator evidence, not completed
physical validation. Historical personal-device results below do not validate rc2.

## Identity and message delivery

Preserve application IDs and compatible protocol semantics:

| Component | Application ID | Project |
| --- | --- | --- |
| Bridge | `a1b2c3d4e5f647589a0b1c2d3e4f5061` | `garmin/MmolioBridge` |
| WatchFace | `b1c2d3e4f5a647589a0b1c2d3e4f5072` | `garmin/MmolioWatchFace` |
| DataField | `7ca56fd800634cab90f28d5e72be2e05` | `garmin/MmolioDataField` |

```text
xDrip4iOS → Connect IQ / Bluetooth → Bridge → private complication → WatchFace
                                 └→ DataField (direct message, while active)
```

The [phone protocol](wire-protocol.md) remains v1, with required integer fields
`v`, `g`, `t`, `m`, `s`, `q` and optional `u` for display units. Glucose stays in
mg/dL on the wire. With the updated sender, `u` follows xDrip's existing unit
preference; legacy messages fall back to local `useMmol` (default mmol/L).

Bridge registers `Background.registerForPhoneAppMessageEvent()` on first opening.
Its background delegate validates and stores the reading, publishes the
complication, then calls `Background.exit(null)`. A publishing error must not
undo the stored value or prevent background exit. Open Bridge once after an update
to register reception and republish stored data with its **original** timestamp.
The `lastReading` storage key and message ordering remain compatible.

## Atomic samples and measurement age

The private complication at index 1 transfers value, trend, measurement time,
units and stale threshold together in one ASCII string. The current publisher
uses internal sample version 2, which also carries glucose range limits; the
shared decoder retains v1 support. This is separate from phone wire version 1.

```text
1|115|5|1700000000|1|900
version|mgdl|trend|measuredAtUnixSeconds|mmolFlag|staleSeconds
```

Bridge and WatchFace must be signed with the **same developer key** for the
private complication to be accessible. The original public complication at index
0 remains for old consumers, but it cannot independently age data after the
publisher stops. The current face uses the timestamp-bearing private sample.
Install matching Bridge and WatchFace versions together.

On every redraw the face computes `now - measuredAt`, independently of message
callbacks. The default stale threshold is **15 minutes**, configurable from 5 to
120 minutes in Bridge.

| State | Display |
| --- | --- |
| Fresh reading | Coloured value, trend, units and age |
| Age at or beyond the threshold | Grey value, STALE and age, no trend arrow |
| Future timestamp | CHECK TIME, no trend arrow |
| Missing/invalid sample or unknown format | -- / NO DATA |
| Unknown trend | ?, never a flat-trend arrow |

Low-power redraws also check age. AMOLED sleep reduces and moves content while
keeping age visible; MIP Fenix retains its layout without AMOLED animation/dimming.
The foreground Bridge refreshes every 30 seconds so a stored reading still ages
when no messages arrive. Heart rate and steps use native Garmin complications;
missing heart rate is `--` and zero steps is valid. Time uses a 24-hour format.
The face does not activate sensors or make network requests.

## DataField

The field does not subscribe to Bridge complications. It receives a separate copy
of each phone packet under its own application ID. The sender must support that
route; installing the `.prg` alone is insufficient with a Bridge-only sender.

- `GlucoseReading.mc` and `GlucoseStore.mc` are compiled directly from Bridge's
  shared files, preserving duplicate/out-of-order rejection. SampleCodec also
  validates field data before it replaces the stored reading.
- The manifest's Background permission accommodates annotations in shared code;
  the field does not register a background service.
- The accepted reading and original time persist across field restarts. Age is
  recomputed on redraw, including while the activity is paused.
- Reception depends on the field running in an activity. Connect IQ may deliver
  queued messages at registration, but delivery to an inactive field is not guaranteed.
- The layout uses actual dimensions and obscured areas, with single/2/3/4-field
  layouts and light/dark activity themes. Limited space may hide units, but not age.
- Phone `u` overrides local display units. Each app otherwise has separate local
  `useMmol`, `staleMinutes` and range settings. Range thresholds remain in mmol/L.
- The field does not control the activity, vibrate or write to FIT.

To add it on FR165, edit an activity's data screens, choose a field and select
**Connect IQ → Mmolio DataField**. Menu wording varies with watch language/firmware.

## Build with Connect IQ SDK 9.2.0

Requirements: Java, SDK **9.2.0**, the relevant device definitions from SDK Manager,
and a developer `.der` signing key kept outside the repository. Use the existing
signing identity when updating installed private-complication applications.

From the repository root on Linux:

```bash
export CONNECTIQ_SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0"
export DEVELOPER_KEY="/path/to/your/developer_key.der"
./garmin/scripts/build-fr165.sh
# Other prepared targets:
./garmin/scripts/build-device.sh fenix7xpro
./garmin/scripts/build-device.sh fenix7xpronowifi
```

Scripts check the SDK version, compile with type checking (`-l 2`) and stop on
failure. Release output is `build/<device>/release/` containing `MmolioBridge.prg`,
`MmolioWatchFace.prg` and `MmolioDataField.prg`. FR255 resources are historical
scaffolding, not a current release target.

Windows developers can build the same projects with `monkeyc.bat`:

```powershell
$Sdk = 'C:\path\to\connectiq-sdk-9.2.0'
$Key = 'C:\path\to\existing\developer_key.der'
New-Item -ItemType Directory -Force build/fr165/release
& "$Sdk\bin\monkeyc.bat" -f garmin/MmolioBridge/monkey.jungle -d fr165 -o build/fr165/release/MmolioBridge.prg -y $Key -l 2 -r
if ($LASTEXITCODE -ne 0) { throw 'Bridge build failed' }
& "$Sdk\bin\monkeyc.bat" -f garmin/MmolioWatchFace/monkey.jungle -d fr165 -o build/fr165/release/MmolioWatchFace.prg -y $Key -l 2 -r
if ($LASTEXITCODE -ne 0) { throw 'WatchFace build failed' }
& "$Sdk\bin\monkeyc.bat" -f garmin/MmolioDataField/monkey.jungle -d fr165 -o build/fr165/release/MmolioDataField.prg -y $Key -l 2 -r
if ($LASTEXITCODE -ne 0) { throw 'DataField build failed' }
```

## Checks and evidence

```bash
.github/scripts/garmin-checks.sh
./garmin/scripts/build-fr165.sh --test
"$CONNECTIQ_SDK/bin/connectiq"
# In another terminal with the simulator running:
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioBridge.prg fr165 -t
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioWatchFace.prg fr165 -t
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioDataField.prg fr165 -t
```

Tests cover publisher/decoder pairing, freshness boundaries, future timestamps,
unknown trends, invalid payloads, units, persistence, ordering and legacy messages.
Tests remove stored samples after use and are excluded from release builds.

For **2026.10.11-rc2**, all nine release builds and **99 simulator tests** passed:
Bridge 11, WatchFace 7 and DataField 15 on each of three devices. Phone-side Xcode
and test evidence is in [PR #771](https://github.com/JohanDegraeve/xdripswift/pull/771).
Structure-only CI does not replace compilation, and simulator checks do not verify
real Bluetooth or background delivery between an iPhone and watches.

Historical evidence is retained in the [Czech technical record](README-CS.md):
September 21 FR165 build/render tests, September 28 personal FR165/DataField use
with xDrip 7.1.1 build 20260925, and [October 3 Fenix tests](../docs/FENIX.md).
These earlier versions are not physical validation of the current candidate.

## USB updates and hardware verification

Use the [installation guide](../docs/GARMIN-INSTALL.md). Back up existing `.prg`
files, identify the exact watch and update only Mmolio apps. Preserve existing
filenames such as `MedProbe.prg` / `xDripWatchFace.prg` rather than installing
duplicate copies of the same IDs. Keep unrelated apps, DATA and SETTINGS intact.
On MTP, read copied files back to verify them before disconnecting.

Open Bridge once, select the face and add the field to an activity. Compare value,
trend, units and age; then test locked-phone reception, low-power display, Bluetooth
loss/reconnect and stale transition without new messages. Record exact commits,
SDK, device/firmware and results. If no physical watch is available, report only
build/simulator checks and leave hardware validation pending.

## SDK references

[Complications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications.html),
[Complication](https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications/Complication.html),
[publishing and access](https://developer.garmin.com/connect-iq/core-topics/complications/),
[WatchFace lifecycle](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/WatchFace.html).
