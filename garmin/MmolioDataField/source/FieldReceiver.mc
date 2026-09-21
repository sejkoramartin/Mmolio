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
            return Mmolio.SampleCodec.decode("1|" + reading.mgdl.format("%d") + "|" +
                reading.trend.format("%d") + "|" + reading.measuredAt.format("%d") + "|" +
                (useMmol ? "1" : "0") + "|" + staleSeconds.format("%d"));
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
