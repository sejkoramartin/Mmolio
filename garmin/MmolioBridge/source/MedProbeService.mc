//
// MedProbeService.mc
//
// Receives readings while the app is closed.
//
// Connect IQ only delivers a phone message to an app that is running. Registering in
// AppBase.initialize covers the foreground; this covers everything else, which for a CGM
// is nearly all of the time — the watch is on a wrist, not in an open app.
//
// Background processes get a small memory budget and see only symbols marked
// (:background), which is why this file and everything it touches carry that annotation.
//

using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;

module MedProbe {

    (:background)
    class MedProbeServiceDelegate extends System.ServiceDelegate {

        function initialize() {
            ServiceDelegate.initialize();
        }

        // Called when the phone sends a message and the app is not in the foreground.
        function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
            var reading = GlucoseReading.fromMessage(msg.data);

            if (reading == null) {
                // Malformed, or from a protocol version this build does not know.
                // Ignoring is deliberate: showing a misread value would be worse than
                // showing the previous one with its age.
                Background.exit(null);
                return;
            }

            if (GlucoseStore.accept(reading)) {
                GlucoseComplication.publish(reading);
            }

            // Ending the background process explicitly returns the memory rather than
            // waiting to be terminated.
            Background.exit(null);
        }
    }
}
