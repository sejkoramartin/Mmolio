using Toybox.Application;
using Toybox.Complications;
using Toybox.WatchUi;

module xDripFace {

    class xDripWatchFaceApp extends Application.AppBase {
        var mComplicationId = null;

        function initialize() {
            AppBase.initialize();
        }

        function onStart(state) {
            findGlucoseComplication();
            Complications.registerComplicationChangeCallback(method(:onComplicationChanged));

            if (mComplicationId != null) {
                Complications.subscribeToUpdates(mComplicationId);
            }
        }

        function onStop(state) {
            Complications.unsubscribeFromAllUpdates();
            Complications.registerComplicationChangeCallback(null);
        }

        function getInitialView() {
            return [new xDripWatchFaceView()];
        }

        function onComplicationChanged(id) {
            if (mComplicationId != null && id.equals(mComplicationId)) {
                WatchUi.requestUpdate();
            } else if (mComplicationId == null) {
                findGlucoseComplication();
                if (mComplicationId != null) {
                    Complications.subscribeToUpdates(mComplicationId);
                    WatchUi.requestUpdate();
                }
            }
        }

        function currentGlucoseValue() {
            if (mComplicationId == null) {
                findGlucoseComplication();
            }

            if (mComplicationId == null) {
                return "--";
            }

            var complication = Complications.getComplication(mComplicationId);
            return complication.value == null ? "--" : complication.value.toString();
        }

        function findGlucoseComplication() {
            var iterator = Complications.getComplications();
            var id = iterator.next();

            while (id != null) {
                var complication = Complications.getComplication(id);

                if (complication.shortLabel == "CGM" ||
                    complication.longLabel == "CGM Glucose") {
                    mComplicationId = id;
                    return;
                }

                id = iterator.next();
            }
        }
    }

    function getApp() {
        return Application.getApp();
    }
}
