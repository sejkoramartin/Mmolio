//
// GlucoseReading.mc
//
// The reading as it arrives from the phone, plus the rules for accepting one.
//
// The wire format is defined on the phone in GarminMessage.swift. Both sides must agree;
// the version field exists because they are updated independently.
//

using Toybox.Lang;
using Toybox.Time;

module MedProbe {

    // Visible to the background process, which receives readings while the app is
    // closed and sees only annotated symbols.
    (:background)
    class GlucoseReading {

        // Protocol version this app understands. A message from a newer phone build is
        // refused rather than misread.
        static const SUPPORTED_VERSION = 1;

        // Wire keys, kept short because Connect IQ transfers are size-limited.
        static const KEY_VERSION = "v";
        static const KEY_MGDL = "g";
        static const KEY_TREND = "t";
        static const KEY_MEASURED_AT = "m";
        static const KEY_SOURCE = "s";
        static const KEY_SEQUENCE = "q";

        var mgdl;
        var trend;
        var measuredAt;   // Unix seconds
        var source;
        var sequence;

        function initialize(glucoseMgdl, trendValue, measuredAtSeconds, sourceValue, sequenceValue) {
            mgdl = glucoseMgdl;
            trend = trendValue;
            measuredAt = measuredAtSeconds;
            source = sourceValue;
            sequence = sequenceValue;
        }

        // Builds a reading from a received dictionary, or null if it cannot be trusted.
        static function fromMessage(payload) {
            if (payload == null || !(payload instanceof Lang.Dictionary)) {
                return null;
            }

            var version = payload.get(KEY_VERSION);
            if (version == null || version != SUPPORTED_VERSION) {
                return null;
            }

            var mgdl = payload.get(KEY_MGDL);
            var trend = payload.get(KEY_TREND);
            var measuredAt = payload.get(KEY_MEASURED_AT);
            var source = payload.get(KEY_SOURCE);
            var sequence = payload.get(KEY_SEQUENCE);

            if (mgdl == null || trend == null || measuredAt == null
                || source == null || sequence == null) {
                return null;
            }

            return new GlucoseReading(mgdl, trend, measuredAt, source, sequence);
        }

        // How old this reading is, in seconds.
        function ageSeconds() {
            return Time.now().value() - measuredAt;
        }

        // Whether it is too old to show as current.
        function isStale(thresholdSeconds) {
            return ageSeconds() >= thresholdSeconds;
        }

        // Whether this reading supersedes another. Applied on the watch as well as the
        // phone, because the transport can redeliver or reorder messages.
        function isNewerThan(other) {
            if (other == null) {
                return true;
            }
            // Sequences are only comparable within one source.
            if (other.source != source) {
                return true;
            }
            if (sequence <= other.sequence) {
                return false;
            }
            return measuredAt >= other.measuredAt;
        }

        function toStorage() {
            return {
                KEY_MGDL => mgdl,
                KEY_TREND => trend,
                KEY_MEASURED_AT => measuredAt,
                KEY_SOURCE => source,
                KEY_SEQUENCE => sequence
            };
        }

        static function fromStorage(stored) {
            if (stored == null || !(stored instanceof Lang.Dictionary)) {
                return null;
            }
            var mgdl = stored.get(KEY_MGDL);
            var trend = stored.get(KEY_TREND);
            var measuredAt = stored.get(KEY_MEASURED_AT);
            var source = stored.get(KEY_SOURCE);
            var sequence = stored.get(KEY_SEQUENCE);

            if (mgdl == null || trend == null || measuredAt == null
                || source == null || sequence == null) {
                return null;
            }
            return new GlucoseReading(mgdl, trend, measuredAt, source, sequence);
        }
    }
}
