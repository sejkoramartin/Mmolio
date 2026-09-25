using Toybox.Complications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

module xDripFace {
    class xDripWatchFaceView extends WatchUi.WatchFace {
        var mSleeping as Lang.Boolean = false;
        var mTimeFont as Graphics.FontType = Graphics.FONT_XTINY;
        var mGlucoseFont as Graphics.FontType = Graphics.FONT_XTINY;
        var mSmallFont as Graphics.FontType = Graphics.FONT_XTINY;
        var mMetricFont as Graphics.FontType = Graphics.FONT_XTINY;
        var mLabelFont as Graphics.FontType = Graphics.FONT_XTINY;
        var mSleepTimeFont as Graphics.FontType = Graphics.FONT_XTINY;
        var mSleepGlucoseFont as Graphics.FontType = Graphics.FONT_XTINY;

        function initialize() { WatchFace.initialize(); }

        function font(size as Lang.Number, fallback as Graphics.FontType) as Graphics.FontType {
            var result = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => size});
            return result == null ? fallback : result;
        }

        function onLayout(dc as Graphics.Dc) as Void {
            mTimeFont = font(104, Graphics.FONT_NUMBER_HOT);
            mGlucoseFont = font(76, Graphics.FONT_NUMBER_MEDIUM);
            mSmallFont = font(23, Graphics.FONT_XTINY);
            mMetricFont = font(32, Graphics.FONT_SMALL);
            mLabelFont = font(18, Graphics.FONT_XTINY);
            mSleepTimeFont = font(72, Graphics.FONT_NUMBER_MEDIUM);
            mSleepGlucoseFont = font(48, Graphics.FONT_NUMBER_MILD);
        }

        // Garmin calls this before the AMOLED display has actually dimmed.
        // Redrawing here makes the reduced face flash while the screen is still bright.
        function onEnterSleep() as Void { }
        function onExitSleep() as Void { WatchUi.requestUpdate(); }

        function onUpdate(dc as Graphics.Dc) as Void {
            mSleeping = System.getDisplayMode() == System.DISPLAY_MODE_LOW_POWER;
            var now = Time.now().value();
            var clock = System.getClockTime();
            var sample = getApp().currentGlucoseSample();
            var heart = getApp().nativeValue(Complications.COMPLICATION_TYPE_HEART_RATE);
            var steps = getApp().nativeValue(Complications.COMPLICATION_TYPE_STEPS);
            var date = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            var dateText = date.day.format("%d") + ". " + (date.month as Lang.Number).format("%d") + ".";
            render(dc, now, clock.hour.format("%02d") + ":" + clock.min.format("%02d"),
                dateText, System.getSystemStats().battery.toNumber(), sample, heart, steps);
        }

        // Fixed 390px FR165 composition. Keeping rendering separate also allows
        // simulator tests to exercise missing, stale and malformed data visually.
        function render(dc as Graphics.Dc, now as Lang.Number, timeText as Lang.String, dateText as Lang.String, battery as Lang.Number, sample as Mmolio.GlucoseSample?, heart as Lang.Number?, steps as Lang.Number?) as Void {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            var cx = dc.getWidth() / 2;
            var stale = sample != null && sample.isStale(now);
            var value = sample == null ? "--" : sample.valueText();
            var color = sample == null || stale ? 0x888888 : 0x65E6CD;
            var timeFont = mSleeping ? mSleepTimeFont : mTimeFont;
            var glucoseFont = mSleeping ? mSleepGlucoseFont : mGlucoseFont;
            // Small minute-based movement and reduced content in AMOLED sleep.
            var shift = mSleeping ? ((now / 60) % 3 - 1) * 4 : 0;
            cx += shift;
            if (!mSleeping) {
                text(dc, cx - 102, 49, mSmallFont, dateText, 0xAAAAAA, Graphics.TEXT_JUSTIFY_LEFT);
                text(dc, cx + 102, 49, mSmallFont, battery.format("%d") + "%", 0xAAAAAA, Graphics.TEXT_JUSTIFY_RIGHT);
            }
            text(dc, cx, 123 + shift, timeFont, timeText,
                mSleeping ? 0x777777 : Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);

            var arrow = sample != null && !stale;
            var width = dc.getTextWidthInPixels(value, glucoseFont);
            var totalWidth = width + (arrow ? 56 : 0);
            var left = cx - totalWidth / 2;
            text(dc, left, 215 + shift, glucoseFont, value,
                mSleeping ? 0x777777 : color, Graphics.TEXT_JUSTIFY_LEFT);
            if (arrow) {
                dc.setColor(mSleeping ? 0x777777 : color, Graphics.COLOR_BLACK);
                drawTrend(dc, left + width + 29, 215 + shift, sample.trend);
            }
            var status = sample == null ? "NO DATA" : sample.ageText(now);
            var unit = sample == null ? "" : sample.unitText() + "  ";
            text(dc, cx, 267 + shift, mSmallFont, unit + status,
                stale ? 0xBBBBBB : 0x888888, Graphics.TEXT_JUSTIFY_CENTER);
            if (!mSleeping) {
                // The native current-HR complication returns null when unavailable.
                metric(dc, cx - 80, heart == null || heart == 0 ? "--" : heart.format("%d"), "BPM");
                metric(dc, cx + 80, steps == null ? "--" : steps.format("%d"), "STEPS");
            }
        }

        function text(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, font as Graphics.FontType, value as Lang.String, color as Lang.Number, alignment as Lang.Number) as Void {
            dc.setColor(color, Graphics.COLOR_BLACK);
            dc.drawText(x, y, font, value, alignment | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        function metric(dc as Graphics.Dc, x as Lang.Number, value as Lang.String, label as Lang.String) as Void {
            // Fit even a six-digit daily step count in its half of the round face.
            var metricFont = dc.getTextWidthInPixels(value, mMetricFont) > 130 ? mSmallFont : mMetricFont;
            text(dc, x, 317, metricFont, value, 0xEEEEEE, Graphics.TEXT_JUSTIFY_CENTER);
            text(dc, x, 345, mLabelFont, label, 0x888888, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Geometric arrows work with every firmware font. Unknown never means flat.
        function drawTrend(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, trend as Lang.Number) as Void {
            if (trend == 0) {
                dc.drawText(x, y, mMetricFont, "?", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }
            var dx = 0;
            var dy = trend <= 3 ? 1 : -1;
            if (trend == 3 || trend == 5) { dx = 1; }
            if (trend == 4) { dx = 1; dy = 0; }
            dc.setPenWidth(4);
            if (trend == 1 || trend == 7) {
                arrowLine(dc, x - 8, y, dx, dy);
                arrowLine(dc, x + 8, y, dx, dy);
            } else { arrowLine(dc, x, y, dx, dy); }
            dc.setPenWidth(1);
        }

        function arrowLine(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, dx as Lang.Number, dy as Lang.Number) as Void {
            var tipX = x + dx * 15;
            var tipY = y + dy * 15;
            dc.drawLine(x - dx * 15, y - dy * 15, tipX, tipY);
            dc.drawLine(tipX, tipY, tipX - dx * 10 - dy * 8, tipY - dy * 10 + dx * 8);
            dc.drawLine(tipX, tipY, tipX - dx * 10 + dy * 8, tipY - dy * 10 - dx * 8);
        }
    }
}
