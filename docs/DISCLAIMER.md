# Mmolio disclaimer

**English** · [Čeština](DISCLAIMER-CS.md)

**Mmolio is not a medical device.** It is a supplemental display of readings
measured by your sensor and sent by your phone application. It does not measure
glucose or make treatment recommendations.

## Treatment decisions

Do not base insulin dosing, food decisions or assessment of your condition on
Mmolio. Use your usual official sensor application and glucose meter.

## Keep your usual alarms enabled

Keep the official sensor application's alarms enabled. Mmolio is a supplemental
display and does not replace those alarms. The Garmin watch app, watch face and
data field do not provide glucose alarms.

## Readings can be old, incorrect or missing

Data passes through multiple devices and, for the optional web route,
the internet. It may be delayed or lost. Measurement age must be calculated from
the original measurement time, not receipt time. The watch marks old readings
`STALE` and future measurement times `CHECK TIME`. A missing or grey display means
that a current reading is unavailable, not that everything is normal.

## No warranty

Mmolio is free software provided without warranty, including merchantability or
fitness for a particular purpose. Use is at your own risk. The author disclaims
liability for damages arising from use, subject to the terms of the
[GPL-3.0 license](../LICENSE).

## Distribution

Source is public under GPL-3.0. Versioned Garmin prerelease installers include
instructions, license, corresponding-source information and validation status.
Other components are built and operated by their users. A successful build or
simulator test does not establish physical-device reliability.

## Trademarks

Dexcom, FreeStyle Libre, Garmin, Connect IQ, Cloudflare and other product names
belong to their owners and are used descriptively. Mmolio is not developed,
endorsed or approved by those companies.

## Your data

The Garmin route sends readings from the phone to the selected watch through
Garmin's SDK and does not require a Mmolio server. The optional web route
sends readings to your own worker on your Cloudflare account.

**The optional worker's read endpoint is public.** Anyone who knows its address
can read the latest value. Do not treat an unshared URL as access control. Keep
that address out of screenshots, public issues and other public material.
