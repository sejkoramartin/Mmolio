# Install Mmolio on your Garmin watch

[Český návod](GARMIN-INSTALL-CS.md) · [Downloads and release notes](https://github.com/sejkoramartin/Mmolio/releases)

Mmolio displays glucose from xDrip4iOS on your watch. You need a compatible iPhone
build with **Garmin Watch** settings, Garmin Connect, a supported watch, a computer
and a USB data cable. No Mmolio server, Nightscout account or watch Wi-Fi is needed
for the phone-to-watch transfer. A cloud glucose source still needs internet.

**The prepared packages are release candidates.** A successful build is not a
physical-device test. Check the validation status in the release notes before
installing. If no release is listed, there is no published binary download yet.
The xDrip integration is being prepared for upstream review; this guide does not
claim that the feature is already included in the official xDrip4iOS release.

Mmolio is a supplemental display with no watch glucose alarms. Read the
[disclaimer](DISCLAIMER-EN.md); keep your usual glucose application and alarms.

## 1. Choose the exact watch

Use the matching ZIP from the release's **Assets** section. Do not download the
GitHub **Source code** archive to install on the watch.

| Watch | Package filename suffix | This candidate's physical validation |
| --- | --- | --- |
| Forerunner 165 | `-fr165.zip` | Pending |
| fēnix 7X Pro | `-fenix7xpro.zip` | Pending |
| fēnix 7X Pro – Solar Edition (no Wi-Fi) | `-fenix7xpronowifi.zip` | Pending |

These filenames use Garmin's SDK product IDs. “Solar” alone is not enough to choose
between the Fenix variants. Match the exact product to the watch's device information
and Garmin model documentation; if uncertain, ask before installing. Whether you
intend to use Wi-Fi does not determine which firmware target you need. Other
Forerunner, Fenix, size and Music variants are not covered by these packages.

## 2. Unzip and install

1. Unzip the package on your computer. Its top-level `START-HERE.txt` identifies
   the exact watch and links to the instructions included inside the ZIP.
2. Connect the watch with a USB **data** cable. Open its storage and locate
   `GARMIN/APPS` (it may be displayed as `GARMIN/Apps`). If the watch does not appear,
   use Garmin's file-transfer instructions for your model and operating system.
3. Copy `MmolioBridge.prg` and `MmolioWatchFace.prg` from the package's `apps` folder
   into `GARMIN/APPS`. Also copy `MmolioDataField.prg` if wanted for activities.
   Copy the files, not the ZIP or the enclosing `apps` folder.
4. Safely disconnect the watch. Open **Mmolio Bridge once**, then select
   **Mmolio WatchFace** as your watch face. Opening Bridge registers background
   phone-message reception.

Bridge receives the readings. WatchFace displays them. DataField is optional and
receives its own copy while running in an activity. Bridge and WatchFace must come
from the same compatible release; their signing identity must match. Published
packages are prepared together so you do not need to compile or sign anything.

## 3. Connect xDrip4iOS

1. Pair the watch with Garmin Connect on your iPhone and allow Bluetooth access.
2. In a compatible xDrip build open **Settings → Sharing and Services → Garmin Watch**.
   If the section is absent, the build does not contain this integration.
3. Turn sharing on and choose **Find / Change Watch**. Authorize the watch in Garmin
   Connect and return to xDrip. If several watches appear, select one in **Watch**.
4. When ready, tap **Resend Latest Reading**. Older personal builds call this
   **Send Test Reading**. It sends the last real reading, not a synthetic test value.
5. Compare the value, trend and measurement age on the watch with xDrip. A recent
   **Last Bridge Transfer** only confirms an SDK transfer, not the watch display.
6. Check several fresh readings with the iPhone locked and Bridge closed. For an
   activity, add **Mmolio DataField** to its data screen and test it while running.

Do not replace a personal/custom xDrip build with another build without checking
its data compatibility. Follow the phone build's own installation instructions.

## 4. Understand the display

| Display | Meaning and action |
| --- | --- |
| `NO DATA` / `--` | No valid reading. Check Bridge installation, open it once, check xDrip selection and Bluetooth. |
| `STALE` | Measurement is too old. Check the phone's latest reading and connection; do not treat receipt time as measurement time. |
| `CHECK TIME` | Measurement time is in the future relative to the watch. Check device clocks. |
| `?` trend | Trend is unknown. This is not a flat/stable trend. |
| Bridge updates but face does not | Install matching Bridge/WatchFace files from one release and reopen Bridge. |
| DataField does not update | Check that it is active and the xDrip build supports direct DataField sending; wait for a new reading. |

The reviewed default stale threshold is 15 minutes. Watch settings and units are
explained in the [Garmin technical guide](../garmin/README.md). Internet loss,
Bluetooth range, iOS suspension, force quit and watch restrictions can delay or
stop delivery. No continuous-background-delivery guarantee is made.

## Updating or removing

Before updating, note your versions and settings and keep copies of the previous
Mmolio files where possible. Older installations may use `MedProbe.prg` and
`xDripWatchFace.prg`: replace the corresponding applications using their existing
filenames, rather than leaving both old and new copies. Update Bridge and WatchFace
together, then open Bridge once. Do not delete unrelated Garmin apps or data.

To stop sending, turn Garmin sharing off in xDrip. Already-submitted packets may
still arrive and the last stored value can remain on the watch with its original
age. To remove Mmolio, first select another watch face/remove the activity field,
then use the watch's app-management procedure to uninstall its components.

## Version, integrity and source

Each ZIP includes the GPL-3.0 license, both disclaimers, these instructions,
`RELEASE.json` (device, version, source revision, SDK and validation status) and
`SHA256SUMS`. The release also includes checksums for the ZIPs. A checksum detects
a changed file; it does not replace trust in the download source or prove hardware
compatibility. Download from the linked Mmolio repository.

The corresponding source revision and source archive URL are in `RELEASE.json`;
source is available separately, without being mixed into the installation ZIP.
See [LICENSE](../LICENSE). Report problems with the package version, watch model
and firmware, iOS/xDrip versions and visible state. Do not post glucose history,
private signing keys or device identifiers.
