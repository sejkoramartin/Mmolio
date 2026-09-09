//
// GlucoseStore.mc
//
// Keeps the last accepted reading, and decides what to accept.
//
// Persisted so a reading survives the background service being restarted between
// messages, which Connect IQ does routinely.
//

using Toybox.Application;
using Toybox.Application.Storage;

module MedProbe {

    // Visible to the background process, which receives readings while the app is
    // closed and sees only annotated symbols.
    (:background)
    class GlucoseStore {

        static const STORAGE_KEY = "lastReading";

        // Default staleness threshold. Both supported sources produce a value every one
        // to two minutes, so fifteen minutes means several cycles have been missed.
        static const DEFAULT_STALE_SECONDS = 900;

        // Reads the stored reading, or null.
        static function load() {
            return GlucoseReading.fromStorage(Storage.getValue(STORAGE_KEY));
        }

        // Stores a reading if it supersedes what we have.
        // Returns true when the stored value changed.
        static function accept(reading) {
            if (reading == null) {
                return false;
            }
            if (!reading.isNewerThan(load())) {
                return false;
            }
            Storage.setValue(STORAGE_KEY, reading.toStorage());
            return true;
        }

        // Staleness threshold in seconds, from settings when the user has set one.
        static function staleThresholdSeconds() {
            var configured = Application.Properties.getValue("staleMinutes");
            if (configured == null || configured <= 0) {
                return DEFAULT_STALE_SECONDS;
            }
            return configured * 60;
        }
    }
}
