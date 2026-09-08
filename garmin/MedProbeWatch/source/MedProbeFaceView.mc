//
// MedProbeFaceView.mc
//
// Watch face that shows the glucose complication.
//
// It reads the complication rather than receiving phone messages, because a face cannot
// register for them. The background app owns the data; this only draws it.
//

using Toybox.Complications;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

module MedProbe {

    class MedProbeFaceView extends WatchUi.WatchFace {

        private var _reading;

        function initialize() {
            WatchFace.initialize();
            _reading = null;
        }

        function onLayout(dc) {
            setLayout(Rez.Layouts.FaceLayout(dc));
        }

        function onShow() {
            refresh();
        }

        // Called once a minute in low-power mode, which is often enough: readings arrive
        // every one to two minutes and the age display only needs minute resolution.
        function onUpdate(dc) {
            refresh();

            var isStale = _reading != null && _reading.isStale(GlucoseStore.staleThresholdSeconds());

            var glucose = View.findDrawableById("faceGlucose");
            if (glucose != null) {
                glucose.setText(Formatter.value(_reading));
                glucose.setColor(isStale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_WHITE);
            }

            var arrow = View.findDrawableById("faceArrow");
            if (arrow != null) {
                arrow.setText(isStale ? "" : Formatter.arrow(_reading));
            }

            var unit = View.findDrawableById("faceUnit");
            if (unit != null) {
                unit.setText(Formatter.unitLabel());
            }

            var age = View.findDrawableById("faceAge");
            if (age != null) {
                if (_reading == null) {
                    age.setText("no data");
                    age.setColor(Graphics.COLOR_DK_GRAY);
                } else if (isStale) {
                    // Never present an old value as current.
                    age.setText("stale " + Formatter.age(_reading));
                    age.setColor(Graphics.COLOR_ORANGE);
                } else {
                    age.setText(Formatter.age(_reading));
                    age.setColor(Graphics.COLOR_LT_GRAY);
                }
            }

            var time = View.findDrawableById("faceTime");
            if (time != null) {
                var now = System.getClockTime();
                time.setText(now.hour.format("%02d") + ":" + now.min.format("%02d"));
            }

            View.onUpdate(dc);
        }

        // Prefers the complication, falling back to storage when the complication is not
        // available on this device or has not been published yet.
        private function refresh() {
            _reading = GlucoseStore.load();
        }

        function onEnterSleep() {
        }

        function onExitSleep() {
        }
    }
}
