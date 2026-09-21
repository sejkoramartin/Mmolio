using Toybox.Application;
using Toybox.Complications;
using Toybox.Lang;
using Toybox.WatchUi;

module xDripFace {

    class xDripWatchFaceApp extends Application.AppBase {

        // Must match GlucoseComplicationLongLabel in the MedProbeWatch resources.
        static const GLUCOSE_LONG_LABEL = "CGM Glucose";

        var mComplicationId as Complications.Id? = null;

        function initialize() {
            AppBase.initialize();
        }

        function onStart(state) {
            Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
            subscribeToGlucose();
        }

        function onStop(state) {
            Complications.unsubscribeFromAllUpdates();
            Complications.registerComplicationChangeCallback(null);
        }

        function getInitialView() {
            return [new xDripWatchFaceView()];
        }

        function onComplicationChanged(id as Complications.Id) as Void {
            if (mComplicationId == null) {
                // The publisher may have been installed after the face started.
                subscribeToGlucose();
            }
            WatchUi.requestUpdate();
        }

        // Returns the published glucose text, or "--" when no publisher is available.
        function currentGlucoseValue() as Lang.String {
            if (mComplicationId == null) {
                subscribeToGlucose();
            }
            if (mComplicationId == null) {
                return "--";
            }

            try {
                var complication = Complications.getComplication(mComplicationId);
                return complication.value == null ? "--" : complication.value.toString();
            } catch (e instanceof Complications.ComplicationNotFoundException) {
                // The publishing app was uninstalled; the system already dropped the
                // subscription.
                mComplicationId = null;
                return "--";
            }
        }

        private function subscribeToGlucose() as Void {
            mComplicationId = findGlucoseComplication();
            if (mComplicationId != null) {
                Complications.subscribeToUpdates(mComplicationId);
            }
        }

        // Connect IQ complications report COMPLICATION_TYPE_INVALID; native ones never
        // carry this label, so the pair identifies the MedProbeWatch publisher.
        private function findGlucoseComplication() as Complications.Id? {
            var iterator = Complications.getComplications();
            var complication = iterator.next();

            while (complication != null) {
                if (complication.getType() == Complications.COMPLICATION_TYPE_INVALID &&
                    complication.longLabel != null &&
                    GLUCOSE_LONG_LABEL.equals(complication.longLabel)) {
                    return complication.complicationId;
                }
                complication = iterator.next();
            }
            return null;
        }
    }

    function getApp() as xDripWatchFaceApp {
        return Application.getApp() as xDripWatchFaceApp;
    }
}
