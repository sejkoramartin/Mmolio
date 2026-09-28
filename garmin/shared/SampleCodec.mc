using Toybox.Lang;

module Mmolio {
    // Internal Bridge -> WatchFace contract; NOT the phone wire protocol.
    //
    //   v1: 1|mgdl|trend|measuredAtUnixSeconds|mmolFlag|staleSeconds
    //   v2: 2|mgdl|trend|measuredAtUnixSeconds|mmolFlag|staleSeconds|lowMgdl|highMgdl
    //
    // v2 adds the in-range limits, so the watch face colours the value and the ring from
    // the Bridge settings instead of its own. A v1 payload from an older Bridge is still
    // accepted and falls back to the default limits.
    class SampleCodec {
        // Names the complication, not the payload version: changing it would make the
        // watch face stop finding the publisher.
        static const LONG_LABEL = "Mmolio Glucose Sample v1";

        static const DEFAULT_LOW_MGDL = 76;    // 4.2 mmol/L
        static const DEFAULT_HIGH_MGDL = 171;  // 9.5 mmol/L

        // Strict canonical integers: toLong alone silently accepts trailing text.
        static function decode(value as Lang.Object?) as GlucoseSample? {
            if (!(value instanceof Lang.String) || value.length() > 120) { return null; }

            var fields = [] as Lang.Array<Lang.Long>;
            var remaining = value;
            while (true) {
                if (fields.size() >= 8) { return null; }
                var separator = remaining.find("|");
                var field = separator == null ? remaining : remaining.substring(0, separator);
                if (field == null) { return null; }
                var number = field.toLong();
                if (number == null || !number.format("%d").equals(field)) { return null; }
                fields.add(number);
                if (separator == null) { break; }
                remaining = remaining.substring(separator + 1, remaining.length()) as Lang.String;
            }

            var version = fields[0];
            if (version == 1) {
                if (fields.size() != 6) { return null; }
            } else if (version == 2) {
                if (fields.size() != 8) { return null; }
            } else {
                return null;
            }

            if (fields[1] <= 0 || fields[1] > 1000 ||
                fields[2] < 0 || fields[2] > 7 || fields[3] <= 0 ||
                fields[3] > 4294967295l || fields[4] < 0 || fields[4] > 1 ||
                fields[5] < 300 || fields[5] > 7200) { return null; }

            var low = DEFAULT_LOW_MGDL;
            var high = DEFAULT_HIGH_MGDL;
            if (version == 2) {
                if (fields[6] <= 0 || fields[7] > 1000 || fields[6] >= fields[7]) { return null; }
                low = fields[6].toNumber();
                high = fields[7].toNumber();
            }

            return new GlucoseSample(fields[1].toNumber(), fields[2].toNumber(),
                fields[3], fields[4] == 1, fields[5].toNumber(), low, high);
        }

    }

    class GlucoseSample {
        var mgdl as Lang.Number;
        var trend as Lang.Number;
        var measuredAt as Lang.Long;
        var useMmol as Lang.Boolean;
        var staleSeconds as Lang.Number;
        var lowMgdl as Lang.Number;
        var highMgdl as Lang.Number;

        function initialize(g as Lang.Number, t as Lang.Number, m as Lang.Long, mmol as Lang.Boolean,
                stale as Lang.Number, low as Lang.Number, high as Lang.Number) {
            mgdl = g; trend = t; measuredAt = m; useMmol = mmol; staleSeconds = stale;
            lowMgdl = low; highMgdl = high;
        }

        function ageSeconds(now as Lang.Number or Lang.Long) as Lang.Long { return now.toLong() - measuredAt; }

        // A future timestamp is also untrusted; never display it as "now".
        function isStale(now as Lang.Number or Lang.Long) as Lang.Boolean {
            var age = ageSeconds(now);
            return age < 0 || age >= staleSeconds;
        }

        // Within the Bridge limits, the same rule the worker and the desktop use.
        // Only ever asked about a fresh reading: a stale one is grey whatever its value.
        function inRange() as Lang.Boolean {
            return mgdl >= lowMgdl && mgdl <= highMgdl;
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
