// The existing public display complication remains at index 0. The private sample at
// index 1 is a SINGLE atomic string: value, trend, measurement time and the in-range
// limits can never be read from different updates. Only same-key Mmolio apps can
// consume it.
using Toybox.Application;
using Toybox.Complications;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;

module MedProbe {
    (:background)
    class GlucoseComplication {
        static const INDEX = 0;
        static const SAMPLE_INDEX = 1;
        static const MGDL_PER_MMOL = 18.0182;
        static const DEFAULT_LOW_MMOL = 4.2;
        static const DEFAULT_HIGH_MMOL = 9.5;

        static function publish(reading) {
            if (reading == null) { return; }
            // Storage was already saved. A platform publishing failure must not
            // prevent Background.exit or stop the proven phone receiver.
            try {
                Complications.updateComplication(SAMPLE_INDEX, {
                    :value => encodeSample(reading, usesMmol(), GlucoseStore.staleThresholdSeconds())
                });
                Complications.updateComplication(INDEX, {
                    :value => displayValue(reading), :shortLabel => "CGM"
                });
            } catch (e) {
                System.println("Mmolio complication unavailable");
            }
        }

        // Versioned atomic payload; built by shared/SampleCodec and checked by
        // round-trip tests. The in-range limits travel with the reading so the watch
        // face colours from the Bridge settings.
        static function encodeSample(reading, useMmol, staleSeconds) {
            // Kept here rather than in the shared codec: the background service only
            // sees annotated code, and annotating the codec would force the Background
            // permission on the watch face too. The round-trip test guards the pairing.
            return "2|" + reading.mgdl.format("%d") + "|" + reading.trend.format("%d") + "|" +
                reading.measuredAt.format("%d") + "|" + (useMmol ? "1" : "0") + "|" +
                staleSeconds.format("%d") + "|" + limitMgdl("lowMmol", DEFAULT_LOW_MMOL).format("%d") +
                "|" + limitMgdl("highMmol", DEFAULT_HIGH_MMOL).format("%d");
        }

        // A limit the user set in mmol/L, as whole mg/dL. Out-of-range or missing
        // settings fall back to the default rather than colouring from nonsense.
        static function limitMgdl(key, fallbackMmol) {
            var configured = Application.Properties.getValue(key);
            var mmol = fallbackMmol;
            if ((configured instanceof Lang.Float || configured instanceof Lang.Double ||
                 configured instanceof Lang.Number) && configured > 1.0 && configured < 30.0) {
                mmol = configured;
            }
            return Math.round(mmol * MGDL_PER_MMOL).toNumber();
        }

        static function usesMmol() {
            var setting = Application.Properties.getValue("useMmol");
            return setting == null ? true : setting;
        }

        static function displayValue(reading) {
            var value = usesMmol() ? (reading.mgdl / MGDL_PER_MMOL).format("%.1f")
                                  : reading.mgdl.format("%d");
            return value + (reading.isStale(GlucoseStore.staleThresholdSeconds())
                ? " STALE" : " " + trendArrow(reading.trend));
        }

        static function trendArrow(trend) {
            switch (trend) {
                case 1: return "↓↓";
                case 2: return "↓";
                case 3: return "↘";
                case 4: return "→";
                case 5: return "↗";
                case 6: return "↑";
                case 7: return "↑↑";
                default: return "?";
            }
        }
    }
}
