//
// GlucoseComplication.mc
//
// Publishes the latest CGM value as a Connect IQ complication so a separate watch face
// can subscribe without needing direct phone communications.
//

using Toybox.Application;
using Toybox.Complications;

module MedProbe {

    (:background)
    class GlucoseComplication {

        static const INDEX = 0;
        static const MGDL_PER_MMOL = 18.0182;

        static function publish(reading) {
            if (reading == null) {
                return;
            }

            var value = displayValue(reading);
            Complications.updateComplication(INDEX, {
                :value => value,
                :shortLabel => "CGM"
            });
        }

        (:background)
        static function displayValue(reading) {
            var useMmol = Application.Properties.getValue("useMmol");
            if (useMmol == null || useMmol) {
                return (reading.mgdl / MGDL_PER_MMOL).format("%.1f") + " " + trendArrow(reading.trend);
            }
            return reading.mgdl.format("%d") + " " + trendArrow(reading.trend);
        }

        (:background)
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
