using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi;

module xDripFace {

    class xDripWatchFaceView extends WatchUi.WatchFace {
        function initialize() {
            WatchFace.initialize();
        }

        function onUpdate(dc) {
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
                Graphics.FONT_NUMBER_MEDIUM,
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
