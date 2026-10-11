# Mmolio for fēnix 7X Pro

**English** · [Čeština](FENIX-CS.md)

Prepared build targets are `fenix7xpro` and `fenix7xpronowifi`. The latter appears
in SDK Manager as **fēnix 7X Pro – Solar Edition (no Wi-Fi)**. Match the exact device
product information; “Solar” alone is insufficient and not using Wi-Fi does not
make the no-Wi-Fi build appropriate.

Both targets use a 280 × 280 MIP display. The face shows time, date, battery,
glucose, trend, age, heart rate and steps. Low-power MIP mode keeps the full ring
and layout without AMOLED animation, movement or dimming. Stale/future readings
turn grey and hide trend/ring. FR165 retains its separate AMOLED behaviour.

## Phone and watch selection

Use a compatible xDrip4iOS Garmin sender and Garmin Connect on the iPhone.
Pair through Garmin Connect, then authorize/select the watch in xDrip's Garmin
settings. The [upstream PR](https://github.com/JohanDegraeve/xdripswift/pull/771)
contains the reviewed sender; `feature/garmin-watch` is the older personal branch.

The sender uses Connect IQ device selection without a watch-model allow-list.
The receiver IDs and wire format are the same across targets. A watch appearing
in the selector is not proof that a reading reached the receiver. Phone-to-watch
transfer uses Bluetooth; watch Wi-Fi is not required.

## Build

Use SDK 9.2.0 and install device definitions for FR165 and both Fenix targets.
Set `CONNECTIQ_SDK` and `DEVELOPER_KEY` as in the [technical guide](../garmin/README.md).
Sign matching components with the same existing key.

```bash
./garmin/scripts/build-device.sh fenix7xpro
./garmin/scripts/build-device.sh fenix7xpronowifi
./garmin/scripts/build-device.sh fenix7xpro --test
```

Outputs are under `build/<device>/release/` or `build/<device>/test/`.
`build-fr165.sh [--test]` remains available for FR165.

## Installation and physical verification

1. Choose the exact target. Check product/device information if uncertain; do not install both variants.
2. Follow the [USB installation guide](GARMIN-INSTALL.md), preserving existing app filenames and unrelated data.
3. Open Bridge once, choose Mmolio WatchFace and enable/select Garmin sharing in xDrip.
4. Compare several fresh readings, including with the iPhone locked and Bridge closed.
5. Check units, trend, age, range colours and low-power mode. Interrupt delivery and verify STALE after the configured threshold, then recovery with a new measurement.
6. Add DataField to an activity and verify its separate reception.

These checks remain pending for the current candidate on physical Fenix devices.
Read the [disclaimer](DISCLAIMER.md).

## Historical local evidence — October 3, 2026

- SDK 9.2.0: all 18 release/test builds passed (3 apps × 3 devices × 2 modes).
- Simulator: Bridge 10/10, WatchFace 7/7, DataField 14/14 per device; 93 tests total.
- Ten watch-face scenarios per model were visually checked: fresh/high, normal/low-power,
  STALE, NO DATA, CHECK TIME, 1000 mg/dL, unknown trend and STALE 12d in low power.
- Both Fenix variants rendered matching screens; fresh MIP normal/low-power views matched pixel-for-pixel.
- FR165 Bridge and DataField matched the control build byte-for-byte using the same SDK/device definitions.
- Structural and build-script syntax checks passed. Physical Fenix/iPhone delivery was not tested.

The later **rc2** candidate passed 99 simulator tests and nine release builds.
Historical visual checks are not a claim that the latest candidate was tested on hardware.
