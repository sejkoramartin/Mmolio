//
// MedProbeApp.mc
//
// Receives glucose readings from the phone and publishes them as a complication.
//
// A watch face cannot receive phone messages, so this app does it instead: it registers
// for Connect IQ messages, stores the newest reading, and exposes it through a
// complication that any face — including the one in this project — can subscribe to.
//

using Toybox.Application;
using Toybox.Communications;
using Toybox.Complications;
using Toybox.System;

module MedProbe {

    class MedProbeApp extends Application.AppBase {

        function initialize() {
            AppBase.initialize();
        }

        function onStart(state) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
            publishComplication();
        }

        function onStop(state) {
        }

        // Called by Connect IQ when the phone sends a message.
        function onPhoneMessage(message) {
            var reading = GlucoseReading.fromMessage(message.data);

            if (reading == null) {
                // Either malformed or from a protocol version this build does not know.
                // Ignoring is deliberate: showing a misread value would be worse than
                // showing the previous one with its age.
                return;
            }

            if (GlucoseStore.accept(reading)) {
                publishComplication();
                WatchUi.requestUpdate();
            }
        }

        function getInitialView() {
            return [new MedProbeView()];
        }

        // Publishes the current reading as a complication for watch faces to read.
        function publishComplication() {
            if (!(Toybox has :Complications)) {
                return;
            }

            var reading = GlucoseStore.load();
            var complication = new Complications.Complication(
                new Complications.Id(Complications.COMPLICATION_TYPE_INVALID)
            );

            if (reading == null) {
                complication.value = null;
                complication.shortLabel = "--";
            } else if (reading.isStale(GlucoseStore.staleThresholdSeconds())) {
                // A stale value is published with its age so a face can mark it, but never
                // as though it were current.
                complication.value = reading.mgdl;
                complication.shortLabel = Formatter.staleLabel(reading);
            } else {
                complication.value = reading.mgdl;
                complication.shortLabel = Formatter.freshLabel(reading);
            }

            Complications.updateComplication(complication);
        }
    }

    function getApp() {
        return Application.getApp();
    }
}
