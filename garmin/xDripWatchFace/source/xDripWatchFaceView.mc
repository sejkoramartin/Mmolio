using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi;

module xDripFace {

    class xDripWatchFaceView extends WatchUi.WatchFace {
        function initialize() {
            WatchFace.initialize();
        }

        function onUpdate(dc as Graphics.Dc) as Void {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();

            var centerX = dc.getWidth() / 2;
            var clock = System.getClockTime();
            var timeText = clock.hour.format("%02d") + ":" + clock.min.format("%02d");

            dc.drawText(
                centerX,
                65,
                Graphics.FONT_MEDIUM,
                timeText,
                Graphics.TEXT_JUSTIFY_CENTER
            );

            var glucose = getApp().currentGlucoseValue();

            dc.drawText(
                centerX,
                170,
                // Number fonts only contain digits; the value carries a trend arrow.
                Graphics.FONT_LARGE,
                glucose,
                Graphics.TEXT_JUSTIFY_CENTER
            );

            dc.drawText(
                centerX,
                235,
                Graphics.FONT_XTINY,
                "xDrip",
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }
}
