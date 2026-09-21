//
// MmolioDataFieldApp.mc
//
// Receives readings from the phone while an activity shows the field. Registering the
// callback also hands over any messages Connect IQ is still holding for the app, but
// delivery to a field that is not running is not guaranteed: the phone may be told the
// send failed. Until the next reading arrives the field shows the stored one with its real
// age. It does not need Mmolio Bridge to be open, and it does not control the activity,
// vibrate or write FIT data.
//

using Toybox.Application;
using Toybox.Communications;

module MmolioField {

    class MmolioDataFieldApp extends Application.AppBase {

        // The last accepted reading, loaded from storage so a restarted field keeps it.
        var mReading = null;

        function initialize() {
            AppBase.initialize();
        }

        function onStart(state) {
            mReading = MedProbe.GlucoseStore.load();
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }

        function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
            if (FieldReceiver.receive(msg.data)) {
                mReading = MedProbe.GlucoseStore.load();
            }
        }

        // Rebuilt on every draw, so age, staleness and settings changes apply once a
        // second even without new messages or while the activity is paused.
        function currentSample() as Mmolio.GlucoseSample? {
            return FieldReceiver.toSample(mReading, FieldReceiver.usesMmol(),
                MedProbe.GlucoseStore.staleThresholdSeconds());
        }

        function getInitialView() {
            return [new MmolioDataFieldView()];
        }
    }

    function getApp() as MmolioDataFieldApp {
        return Application.getApp() as MmolioDataFieldApp;
    }
}
