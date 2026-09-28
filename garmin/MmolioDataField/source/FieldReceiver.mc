//
// FieldReceiver.mc
//
// Accepts phone v1 packets for the data field and turns the stored reading into a sample.
//
// Parsing and ordering are Bridge's own GlucoseReading and GlucoseStore, so duplicates,
// redeliveries and older sequences are refused exactly as in Bridge. Before storing, the
// reading must also survive Mmolio.SampleCodec, the validator Mmolio WatchFace applies to
// the same values — the field never keeps a value the face would refuse.
//

using Toybox.Application;
using Toybox.Lang;
using Toybox.Math;

module MmolioField {

    class FieldReceiver {

        // Returns true when the packet was valid and newer than the stored reading.
        static function receive(payload) as Lang.Boolean {
            var reading = MedProbe.GlucoseReading.fromMessage(payload);
            // Validity does not depend on the user's display settings.
            if (toSample(reading, true, MedProbe.GlucoseStore.DEFAULT_STALE_SECONDS) == null) {
                return false;
            }
            return MedProbe.GlucoseStore.accept(reading);
        }

        // The reading as a display sample, or null when it cannot be trusted. The sample
        // keeps the measurement time; age is always computed from it, never from receipt.
        static function toSample(reading, useMmol as Lang.Boolean, staleSeconds as Lang.Number) as Mmolio.GlucoseSample? {
            if (reading == null ||
                !isInteger(reading.mgdl) || !isInteger(reading.trend) ||
                !isInteger(reading.measuredAt) || !isInteger(reading.source) ||
                !isInteger(reading.sequence)) {
                return null;
            }
            return Mmolio.SampleCodec.decode("2|" + reading.mgdl.format("%d") + "|" +
                reading.trend.format("%d") + "|" + reading.measuredAt.format("%d") + "|" +
                (useMmol ? "1" : "0") + "|" + staleSeconds.format("%d") + "|" +
                limitMgdl("lowMmol", 4.2).format("%d") + "|" +
                limitMgdl("highMmol", 9.5).format("%d"));
        }

        // An in-range limit the user set in mmol/L, as whole mg/dL. Out-of-range or
        // missing settings fall back to the default rather than colouring from nonsense.
        static function limitMgdl(key as Lang.String, fallbackMmol as Lang.Float) as Lang.Number {
            var configured = Application.Properties.getValue(key);
            var mmol = fallbackMmol;
            if ((configured instanceof Lang.Float || configured instanceof Lang.Double ||
                 configured instanceof Lang.Number) && configured > 1.0 && configured < 30.0) {
                mmol = configured;
            }
            return Math.round(mmol * 18.0182).toNumber();
        }

        // Settings are the field's own, independent of Mmolio Bridge.
        static function usesMmol() as Lang.Boolean {
            var setting = Application.Properties.getValue("useMmol");
            return setting instanceof Lang.Boolean ? setting : true;
        }

        private static function isInteger(value) as Lang.Boolean {
            return value instanceof Lang.Number || value instanceof Lang.Long;
        }
    }
}
