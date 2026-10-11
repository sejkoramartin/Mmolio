# Mmolio

**English** · [Čeština](README-CS.md)

Display CGM glucose readings on Garmin watches and a spare phone or tablet.
Mmolio receives readings from a phone application; it does not measure glucose itself.

**Garmin installation:** [English guide](docs/GARMIN-INSTALL.md) · [Český návod](docs/GARMIN-INSTALL-CS.md)

**Downloads:** [Garmin release candidates](https://github.com/sejkoramartin/Mmolio/releases).
Choose the ZIP for your exact watch model. Each installer includes the watch apps,
instructions, license and disclaimers, without source files or the worker.

> **Mmolio is not a medical device.** It is a supplemental display, not a basis for
> treatment decisions. Keep your usual sensor application's alarms enabled.
> Read the [disclaimer](docs/DISCLAIMER.md).

## Garmin: direct phone-to-watch sharing

```text
CGM / follower → xDrip4iOS on iPhone → Connect IQ / Bluetooth → Mmolio Bridge → WatchFace
                                                           └→ Mmolio DataField (during activities)
```

The phone-to-watch transfer needs no Nightscout server, Mmolio worker or watch Wi-Fi.
Cloud-based glucose sources still need their usual internet connection. With an
updated xDrip sender and Mmolio rc2 or later, display units automatically follow
xDrip's existing mmol/L or mg/dL setting.

Prepared receiver targets: **Forerunner 165**, **fēnix 7X Pro** and
**fēnix 7X Pro – Solar Edition (no Wi-Fi)**. Match the exact product ID; “Solar” alone
is not enough to select a package. The current packages are **prereleases**:
receiver builds and simulator tests passed, but physical validation of this
candidate remains pending for every model.

The iPhone sender is maintained separately in
[xDrip4iOS draft PR #771](https://github.com/JohanDegraeve/xdripswift/pull/771), on
[`feature/garmin-connectiq-upstream`](https://github.com/sejkoramartin/xdripswift/tree/feature/garmin-connectiq-upstream).
It is not yet claimed to be part of the official xDrip release. The unsigned Xcode
build and Garmin tests passed; the full simulator suite has failures also found
in upstream. See the PR for detailed evidence and remaining hardware tests.

## Repository contents

| Directory | Component |
| --- | --- |
| [garmin/](garmin/README.md) | Bridge receiver, WatchFace and optional activity DataField |
| [worker/](worker/README.md) | Optional self-hosted Cloudflare receiver and web display |
| [docs/](docs/README.md) | Installation guides, FAQ, disclaimers and development notes |

The web route is separate from Garmin:

```text
xDrip4iOS → HTTPS → your Cloudflare Worker → phone/tablet web display
```

Use only the components you need. The worker is configured with your own account
and upload secret; Mmolio does not need your sensor-service password. The optional
worker's read endpoint is public to anyone who knows its URL; see the disclaimer.

## Installation and development

- [Install Garmin apps from a release ZIP](docs/GARMIN-INSTALL.md)
- [Set up optional web components](docs/INSTALL.md)
- [Troubleshooting / FAQ](docs/FAQ.md)
- [Garmin build instructions](garmin/README.md) and [phone protocol](garmin/wire-protocol.md)

Source code remains available under GPL-3.0. Garmin installation ZIPs do not require
users to compile; developers can reproduce builds from the exact source revision
recorded in each package's `RELEASE.json`.

## Measurement age

**An old reading must never appear current.** Age is measured from the original
measurement time, not the time it arrived. The watch marks old readings `STALE`
and hides the trend arrow. Missing, old or future-dated data must not be interpreted
as a current valid measurement.

## License

[GNU GPL v3](LICENSE), without warranty. Dexcom, FreeStyle Libre, Garmin, Connect IQ,
Cloudflare and other product names belong to their respective owners. Mmolio is
not developed, endorsed or approved by those companies.
