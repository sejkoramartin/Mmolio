using Toybox.Lang;

module Mmolio {
    // Internal Bridge -> WatchFace contract; NOT the phone wire protocol.
    // ASCII: version|mgdl|trend|measuredAtUnixSeconds|mmolFlag|staleSeconds.
    class SampleCodec {
        static const LONG_LABEL = "Mmolio Glucose Sample v1";

        // Strict canonical integers: toLong alone silently accepts trailing text.
        static function decode(value as Lang.Object?) as GlucoseSample? {
            if (!(value instanceof Lang.String) || value.length() > 80) { return null; }
            var fields = [] as Lang.Array<Lang.Long>;
            var remaining = value;
            for (var i = 0; i < 6; i += 1) {
                var separator = remaining.find("|");
                if ((i < 5 && separator == null) || (i == 5 && separator != null)) {
                    return null;
                }
                var field = separator == null ? remaining : remaining.substring(0, separator);
                if (field == null) { return null; }
                var number = field.toLong();
                if (number == null || !number.format("%d").equals(field)) { return null; }
                fields.add(number);
                if (separator != null) { remaining = remaining.substring(separator + 1, remaining.length()) as Lang.String; }
            }
            if (fields[0] != 1 || fields[1] <= 0 || fields[1] > 1000 ||
                fields[2] < 0 || fields[2] > 7 || fields[3] <= 0 ||
                fields[3] > 4294967295l || fields[4] < 0 || fields[4] > 1 ||
                fields[5] < 300 || fields[5] > 7200) { return null; }
            return new GlucoseSample(fields[1].toNumber(), fields[2].toNumber(),
                fields[3], fields[4] == 1, fields[5].toNumber());
        }
    }

    class GlucoseSample {
        var mgdl as Lang.Number;
        var trend as Lang.Number;
        var measuredAt as Lang.Long;
        var useMmol as Lang.Boolean;
        var staleSeconds as Lang.Number;

        function initialize(g as Lang.Number, t as Lang.Number, m as Lang.Long, mmol as Lang.Boolean, stale as Lang.Number) {
            mgdl = g; trend = t; measuredAt = m; useMmol = mmol; staleSeconds = stale;
        }

        function ageSeconds(now as Lang.Number or Lang.Long) as Lang.Long { return now.toLong() - measuredAt; }

        // A future timestamp is also untrusted; never display it as "now".
        function isStale(now as Lang.Number or Lang.Long) as Lang.Boolean {
            var age = ageSeconds(now);
            return age < 0 || age >= staleSeconds;
        }

        function valueText() as Lang.String {
            return useMmol ? (mgdl / 18.0182).format("%.1f") : mgdl.format("%d");
        }

        function unitText() as Lang.String { return useMmol ? "mmol/L" : "mg/dL"; }

        function ageText(now as Lang.Number or Lang.Long) as Lang.String {
            var age = ageSeconds(now);
            if (age < 0) { return "CHECK TIME"; }
            var minutes = age / 60;
            var text = "";
            if (minutes < 1) { text = "<1m"; }
            else if (minutes < 60) { text = minutes.format("%d") + "m"; }
            else if (minutes < 1440) { text = (minutes / 60).format("%d") + "h" + (minutes % 60).format("%d") + "m"; }
            else { text = (minutes / 1440).format("%d") + "d"; }
            return (isStale(now) ? "STALE " : "") + text;
        }
    }
}
