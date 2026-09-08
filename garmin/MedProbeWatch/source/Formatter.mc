//
// Formatter.mc
//
// Turning a reading into what the user sees.
//
// Every function here treats a stale reading as stale. Nothing formats an old value as
// though it were current — that is the one rule this file exists to enforce.
//

using Toybox.Application;
using Toybox.Lang;
using Toybox.Math;

module MedProbe {

    class Formatter {

        // mg/dL per mmol/L.
        static const MGDL_PER_MMOL = 18.0182;

        // Trend wire values, matching GlucoseTrend on the phone.
        static const TREND_UNKNOWN = 0;
        static const TREND_FALLING_QUICKLY = 1;
        static const TREND_FALLING = 2;
        static const TREND_FALLING_SLIGHTLY = 3;
        static const TREND_STEADY = 4;
        static const TREND_RISING_SLIGHTLY = 5;
        static const TREND_RISING = 6;
        static const TREND_RISING_QUICKLY = 7;

        // Whether the user wants mmol/L. Defaults to mmol/L, which is what both
        // supported regions for this project use.
        static function usesMmol() {
            var setting = Application.Properties.getValue("useMmol");
            return setting == null ? true : setting;
        }

        static function unitLabel() {
            return usesMmol() ? "mmol/L" : "mg/dL";
        }

        // The glucose value as a display string.
        static function value(reading) {
            if (reading == null) {
                return "--";
            }
            if (usesMmol()) {
                var mmol = reading.mgdl / MGDL_PER_MMOL;
                return mmol.format("%.1f");
            }
            return reading.mgdl.format("%d");
        }

        // Trend arrow. Unknown is a question mark, never a flat arrow: a missing trend
        // must not read as "steady".
        static function arrow(reading) {
            if (reading == null) {
                return "";
            }
            switch (reading.trend) {
                case TREND_FALLING_QUICKLY:  return "↓↓";
                case TREND_FALLING:          return "↓";
                case TREND_FALLING_SLIGHTLY: return "↘";
                case TREND_STEADY:           return "→";
                case TREND_RISING_SLIGHTLY:  return "↗";
                case TREND_RISING:           return "↑";
                case TREND_RISING_QUICKLY:   return "↑↑";
                default:                     return "?";
            }
        }

        // Age as a short string: "3m", "1h12m".
        static function age(reading) {
            if (reading == null) {
                return "";
            }
            var seconds = reading.ageSeconds();
            if (seconds < 60) {
                return "now";
            }
            var minutes = seconds / 60;
            if (minutes < 60) {
                return minutes.format("%d") + "m";
            }
            var hours = minutes / 60;
            return hours.format("%d") + "h" + (minutes % 60).format("%d") + "m";
        }

        static function freshLabel(reading) {
            return value(reading) + " " + arrow(reading);
        }

        // A stale reading is labelled as such wherever it appears.
        static function staleLabel(reading) {
            return value(reading) + " (" + age(reading) + ")";
        }

        static function sourceName(reading) {
            if (reading == null) {
                return "";
            }
            return reading.source == 2 ? "Libre" : "Medtrum";
        }
    }
}
