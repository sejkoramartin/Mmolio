using Toybox.Complications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Timer;
using Toybox.WatchUi;

module xDripFace {
    class xDripWatchFaceView extends WatchUi.WatchFace {

        // The colours the worker and the desktop display already use.
        static const COLOR_IN_RANGE = 0x33CC55;
        static const COLOR_OUT_OF_RANGE = 0xFF4444;
        static const COLOR_UNTRUSTED = 0x888888;

        static const RIM_WIDTH = 5;
        // A lap of the rim: out of range runs twice as fast, awake and asleep alike.
        static const AWAKE_LAP_MS = 10000;
        static const SLEEP_STEP_DEGREES = 6;
        static const TAIL_SEGMENTS = 6;
        static const TAIL_SEGMENT_DEGREES = 7;

        var mSleeping as Lang.Boolean = false;
        var mTimer as Timer.Timer? = null;
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

        // Timers exist only in high power mode, so the running head is animated while
        // the watch is awake and steps once a minute in always-on.
        function onShow() as Void { startAnimation(); }
        function onHide() as Void { stopAnimation(); }

        function onEnterSleep() as Void {
            mSleeping = true;
            stopAnimation();
            WatchUi.requestUpdate();
        }

        function onExitSleep() as Void {
            mSleeping = false;
            startAnimation();
            WatchUi.requestUpdate();
        }

        private function startAnimation() as Void {
            if (mTimer != null || mSleeping) { return; }
            mTimer = new Timer.Timer();
            (mTimer as Timer.Timer).start(method(:onAnimationTick), 100, true);
        }

        private function stopAnimation() as Void {
            if (mTimer == null) { return; }
            (mTimer as Timer.Timer).stop();
            mTimer = null;
        }

        function onAnimationTick() as Void { WatchUi.requestUpdate(); }

        function onUpdate(dc as Graphics.Dc) as Void {
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
            var trusted = sample != null && !stale;
            var value = sample == null ? "--" : sample.valueText();
            // Range colours belong to a reading we trust; anything else stays grey.
            var color = !trusted ? COLOR_UNTRUSTED
                : (sample.inRange() ? COLOR_IN_RANGE : COLOR_OUT_OF_RANGE);
            drawRim(dc, now, color, trusted, trusted && !sample.inRange());
            var timeFont = mSleeping ? mSleepTimeFont : mTimeFont;
            var glucoseFont = mSleeping ? mSleepGlucoseFont : mGlucoseFont;
            // Small minute-based movement and reduced content in AMOLED sleep.
            var shift = mSleeping ? ((now / 60) % 3 - 1) * 4 : 0;
            cx += shift;
            // Secondary values stay readable in always-on, only dimmed and moving with
            // the rest: a few thousand lit pixels at this brightness are far below what
            // the AMOLED always-on budget allows.
            var secondary = mSleeping ? 0x555555 : 0xAAAAAA;
            text(dc, cx - 102, 49 + shift, mSmallFont, dateText, secondary, Graphics.TEXT_JUSTIFY_LEFT);
            text(dc, cx + 102, 49 + shift, mSmallFont, battery.format("%d") + "%", secondary,
                Graphics.TEXT_JUSTIFY_RIGHT);
            text(dc, cx, 123 + shift, timeFont, timeText,
                mSleeping ? 0x777777 : Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);

            var arrow = sample != null && !stale;
            var width = dc.getTextWidthInPixels(value, glucoseFont);
            var totalWidth = width + (arrow ? 56 : 0);
            var left = cx - totalWidth / 2;
            var valueColor = mSleeping ? dim(color, 45) : color;
            text(dc, left, 215 + shift, glucoseFont, value,
                valueColor, Graphics.TEXT_JUSTIFY_LEFT);
            if (arrow) {
                dc.setColor(valueColor, Graphics.COLOR_BLACK);
                drawTrend(dc, left + width + 29, 215 + shift, sample.trend);
            }
            var status = sample == null ? "NO DATA" : sample.ageText(now);
            var unit = sample == null ? "" : sample.unitText() + "  ";
            text(dc, cx, 267 + shift, mSmallFont, unit + status,
                stale ? 0xBBBBBB : 0x888888, Graphics.TEXT_JUSTIFY_CENTER);
            // The native current-HR complication returns null when unavailable.
            metric(dc, cx - 80, shift, heart == null || heart == 0 ? "--" : heart.format("%d"), "BPM");
            metric(dc, cx + 80, shift, steps == null ? "--" : steps.format("%d"), "STEPS");
        }

        // Awake: the whole rim glows in the range colour with a brighter head running
        // around it. Always-on: only the head and its fading tail, one step per minute,
        // so nothing on the rim stays lit — the rule AMOLED burn-in protection applies.
        function drawRim(dc as Graphics.Dc, now as Lang.Number or Lang.Long, color as Lang.Number,
                trusted as Lang.Boolean, fast as Lang.Boolean) as Void {
            if (!trusted) { return; }

            var centerX = dc.getWidth() / 2;
            var centerY = dc.getHeight() / 2;
            var radius = centerX - (RIM_WIDTH + 1) / 2;
            var head;

            dc.setPenWidth(RIM_WIDTH);
            if (!mSleeping) {
                dc.setColor(dim(color, 35), Graphics.COLOR_BLACK);
                dc.drawCircle(centerX, centerY, radius);
                var lap = fast ? AWAKE_LAP_MS / 2 : AWAKE_LAP_MS;
                head = 90 - (System.getTimer() % lap) * 360 / lap;
            } else {
                var step = fast ? SLEEP_STEP_DEGREES * 2 : SLEEP_STEP_DEGREES;
                head = 90 - ((now / 60) * step) % 360;
            }

            // Drawn from the head backwards, each segment dimmer than the one before.
            for (var i = 0; i < TAIL_SEGMENTS; i += 1) {
                var brightness = 100 - i * (100 / TAIL_SEGMENTS);
                dc.setColor(dim(color, brightness), Graphics.COLOR_BLACK);
                dc.drawArc(centerX, centerY, radius, Graphics.ARC_COUNTER_CLOCKWISE,
                    head + i * TAIL_SEGMENT_DEGREES, head + (i + 1) * TAIL_SEGMENT_DEGREES);
            }
            dc.setPenWidth(1);
        }

        // percent 0-100 of the original colour, on black.
        function dim(color as Lang.Number, percent as Lang.Number) as Lang.Number {
            var red = ((color >> 16) & 0xFF) * percent / 100;
            var green = ((color >> 8) & 0xFF) * percent / 100;
            var blue = (color & 0xFF) * percent / 100;
            return (red << 16) | (green << 8) | blue;
        }

        function text(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, font as Graphics.FontType, value as Lang.String, color as Lang.Number, alignment as Lang.Number) as Void {
            dc.setColor(color, Graphics.COLOR_BLACK);
            dc.drawText(x, y, font, value, alignment | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        function metric(dc as Graphics.Dc, x as Lang.Number, shift as Lang.Number, value as Lang.String, label as Lang.String) as Void {
            // Fit even a six-digit daily step count in its half of the round face.
            var metricFont = dc.getTextWidthInPixels(value, mMetricFont) > 130 ? mSmallFont : mMetricFont;
            text(dc, x, 317 + shift, metricFont, value, mSleeping ? 0x666666 : 0xEEEEEE,
                Graphics.TEXT_JUSTIFY_CENTER);
            text(dc, x, 345 + shift, mLabelFont, label, mSleeping ? 0x444444 : 0x888888,
                Graphics.TEXT_JUSTIFY_CENTER);
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
