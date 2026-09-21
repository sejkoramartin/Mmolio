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
using Toybox.Background;
using Toybox.Communications;
using Toybox.System;
using Toybox.WatchUi;

module MedProbe {

    class MedProbeApp extends Application.AppBase {

        function initialize() {
            AppBase.initialize();
        }

        function onStart(state) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }

        function onStop(state) {
        }

        // Called by Connect IQ when the phone sends a message.
        // The parameter type is fixed by the SDK; a looser one is rejected at compile time.
        function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
            var reading = GlucoseReading.fromMessage(msg.data);

            if (reading == null) {
                // Either malformed or from a protocol version this build does not know.
                // Ignoring is deliberate: showing a misread value would be worse than
                // showing the previous one with its age.
                return;
            }

            if (GlucoseStore.accept(reading)) {
                GlucoseComplication.publish(reading);
                WatchUi.requestUpdate();
            }
        }

        function getInitialView() {
            registerBackgroundReceiver();
            GlucoseComplication.publish(GlucoseStore.load());
            return [new MedProbeView()];
        }

        // Without this registration the system never wakes MedProbeServiceDelegate, and
        // readings only arrive while the app is open. It persists across app restarts, so
        // it is enough that the app has been opened once. getInitialView only runs in the
        // foreground process, which is where the registration has to happen.
        function registerBackgroundReceiver() as Void {
            if ((Toybox has :Background) && (Background has :registerForPhoneAppMessageEvent)) {
                Background.registerForPhoneAppMessageEvent();
            }
        }

        function onSettingsChanged() as Void {
            GlucoseComplication.publish(GlucoseStore.load());
            WatchUi.requestUpdate();
        }

        function onBackgroundData(data) as Void {
            WatchUi.requestUpdate();
        }

        // Registers the background service, so readings arrive while the app is closed.
        function getServiceDelegate() {
            return [new MedProbeServiceDelegate()];
        }

    }

    function getApp() {
        return Application.getApp();
    }
}
