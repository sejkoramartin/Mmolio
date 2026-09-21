using Toybox.Application;
using Toybox.Complications;
using Toybox.Lang;
using Toybox.WatchUi;

module xDripFace {
    class xDripWatchFaceApp extends Application.AppBase {
        var mComplicationId as Complications.Id? = null;

        function initialize() { AppBase.initialize(); }

        function onStart(state) {
            Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
            subscribeToGlucose();
            subscribeNative(Complications.COMPLICATION_TYPE_HEART_RATE);
            subscribeNative(Complications.COMPLICATION_TYPE_STEPS);
        }

        function onStop(state) {
            Complications.unsubscribeFromAllUpdates();
            Complications.registerComplicationChangeCallback(null);
        }

        function getInitialView() { return [new xDripWatchFaceView()]; }

        function onComplicationChanged(id as Complications.Id) as Void {
            WatchUi.requestUpdate();
        }

        // Never fall back to the old display string: it has no measurement time.
        // Re-read on every draw, including minute updates without any phone events.
        function currentGlucoseSample() as Mmolio.GlucoseSample? {
            if (mComplicationId == null) { subscribeToGlucose(); }
            if (mComplicationId == null) { return null; }
            try {
                return Mmolio.SampleCodec.decode(Complications.getComplication(mComplicationId).value);
            } catch (e instanceof Complications.ComplicationNotFoundException) {
                mComplicationId = null;
                return null;
            }
        }

        function nativeValue(type as Complications.Type) as Lang.Number? {
            try {
                var value = Complications.getComplication(new Complications.Id(type)).value;
                if (value instanceof Lang.Number && value >= 0) { return value; }
            } catch (e instanceof Complications.ComplicationNotFoundException) {
                // Unavailable metrics are shown as --, never cached as current.
            }
            return null;
        }

        private function subscribeNative(type as Complications.Type) as Void {
            try { Complications.subscribeToUpdates(new Complications.Id(type)); }
            catch (e instanceof Complications.ComplicationNotFoundException) { }
        }

        private function subscribeToGlucose() as Void {
            var iterator = Complications.getComplications();
            var complication = iterator.next();
            while (complication != null) {
                if (complication.getType() == Complications.COMPLICATION_TYPE_INVALID &&
                    Mmolio.SampleCodec.LONG_LABEL.equals(complication.longLabel)) {
                    mComplicationId = complication.complicationId;
                    try { Complications.subscribeToUpdates(complication.complicationId); }
                    catch (e instanceof Complications.ComplicationNotFoundException) { mComplicationId = null; }
                    return;
                }
                complication = iterator.next();
            }
        }
    }

    function getApp() as xDripWatchFaceApp {
        return Application.getApp() as xDripWatchFaceApp;
    }
}
