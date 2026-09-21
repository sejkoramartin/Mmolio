// The existing public display complication remains at index 0. The private v1
// sample is a SINGLE atomic string: value, trend and measurement time can never
// be read from different updates. Only same-key Mmolio apps can consume it.
using Toybox.Application;
using Toybox.Complications;
using Toybox.System;

module MedProbe {
    (:background)
    class GlucoseComplication {
        static const INDEX = 0;
        static const SAMPLE_INDEX = 1;
        static const MGDL_PER_MMOL = 18.0182;

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

        // Versioned atomic payload; mirrored by shared/SampleCodec and round-trip tests.
        static function encodeSample(reading, useMmol, staleSeconds) {
            return "1|" + reading.mgdl.format("%d") + "|" + reading.trend.format("%d") + "|" +
                reading.measuredAt.format("%d") + "|" + (useMmol ? "1" : "0") + "|" +
                staleSeconds.format("%d");
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
