//
// FieldRenderer.mc
//
// Draws the field into any rectangle: a full screen, a half, or a quarter of the compact
// four-field layout. Nothing is sized for 390 px; fonts are chosen by fitting the text into
// the part of the rectangle a round screen actually shows.
//

using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;

module MmolioField {

    class FieldRenderer {

        static const VECTOR_SIZES = [150, 128, 110, 96, 84, 72, 62, 54, 46, 40, 34, 29, 25, 21, 18];

        var mFonts as Lang.Array<Graphics.FontType> = [] as Lang.Array<Graphics.FontType>;
        var mScreenWidth as Lang.Number;
        var mScreenHeight as Lang.Number;
        var mRound as Lang.Boolean;

        function initialize() {
            for (var i = 0; i < VECTOR_SIZES.size(); i += 1) {
                var font = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => VECTOR_SIZES[i]});
                if (font != null) { mFonts.add(font); }
            }
            if (mFonts.size() == 0) {
                mFonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
                    Graphics.FONT_TINY, Graphics.FONT_XTINY] as Lang.Array<Graphics.FontType>;
            }
            var settings = System.getDeviceSettings();
            mScreenWidth = settings.screenWidth;
            mScreenHeight = settings.screenHeight;
            mRound = settings.screenShape == System.SCREEN_SHAPE_ROUND;
        }

        // x, y, width, height: the field rectangle within dc. flags: DataField.OBSCURE_*.
        function draw(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, width as Lang.Number,
                height as Lang.Number, flags as Lang.Number, dark as Lang.Boolean,
                now as Lang.Number or Lang.Long, sample as Mmolio.GlucoseSample?) as Void {
            var background = dark ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
            dc.setColor(background, background);
            dc.fillRectangle(x, y, width, height);

            var stale = sample != null && sample.isStale(now);
            var value = sample == null ? "--" : sample.valueText();
            var status = sample == null ? "NO DATA" : sample.ageText(now);
            // The unit is dropped before the age whenever space runs out.
            var statuses = sample == null ? [status] : [sample.unitText() + "  " + status, status];
            var trend = sample == null || stale ? -1 : sample.trend;
            // The colours the worker and the desktop use. A reading we cannot trust is
            // grey whatever its value, so an old one never reads as in range.
            var valueColor;
            if (sample == null || stale) {
                valueColor = dark ? 0x888888 : 0x777777;
            } else if (sample.inRange()) {
                valueColor = dark ? 0x33CC55 : 0x1E8C3A;
            } else {
                valueColor = dark ? 0xFF4444 : 0xC62828;
            }
            var statusColor = stale ? (dark ? 0xDDDDDD : 0x222222) : (dark ? 0xAAAAAA : 0x555555);

            // Where the rectangle sits on screen; only the obscurity flags tell us.
            var left = (flags & WatchUi.DataField.OBSCURE_LEFT) != 0;
            var right = (flags & WatchUi.DataField.OBSCURE_RIGHT) != 0;
            var top = (flags & WatchUi.DataField.OBSCURE_TOP) != 0;
            var bottom = (flags & WatchUi.DataField.OBSCURE_BOTTOM) != 0;
            var screenX = left && !right ? 0 : (right && !left ? mScreenWidth - width : (mScreenWidth - width) / 2);
            var screenY = top && !bottom ? 0 : (bottom && !top ? mScreenHeight - height : (mScreenHeight - height) / 2);

            // First pass keeps the unit; only if no font fits is it dropped.
            var pad = max(2, height / 25);
            var count = mFonts.size();
            for (var attempt = 0; attempt < 2 * count; attempt += 1) {
                var i = attempt % count;
                var allowed = attempt < count ? [statuses[0]] : statuses;
                var valueFont = mFonts[i];
                var valueHeight = (Graphics.getFontHeight(valueFont) * 0.78).toNumber();
                var statusFont = statusFontFor(valueHeight);
                var statusHeight = (Graphics.getFontHeight(statusFont) * 0.9).toNumber();
                var gap = max(1, valueHeight / 12);
                var total = valueHeight + gap + statusHeight;
                var last = attempt + 1 == 2 * count;
                if (total > height - 2 * pad && !last) { continue; }

                // A field cut by the top of the circle keeps its content low, and vice versa.
                var blockTop = top && !bottom ? height - pad - total
                             : (bottom && !top ? pad : (height - total) / 2);
                var valueSpan = visibleSpan(blockTop, blockTop + valueHeight, width, screenX, screenY);
                var statusSpan = visibleSpan(blockTop + valueHeight + gap, blockTop + total, width, screenX, screenY);
                var arrowWidth = trendWidth(dc, trend, valueHeight, statusFont);
                var valueWidth = dc.getTextWidthInPixels(value, valueFont) + arrowWidth;
                var inset = max(3, width / 30);
                var statusText = fitting(dc, allowed, statusFont, statusSpan[1] - statusSpan[0] - 2 * inset);
                if (!last && (valueWidth > valueSpan[1] - valueSpan[0] - 2 * inset || statusText == null)) {
                    continue;
                }

                var valueY = y + blockTop + valueHeight / 2;
                var valueLeft = x + (valueSpan[0] + valueSpan[1]) / 2 - valueWidth / 2;
                dc.setColor(valueColor, background);
                dc.drawText(valueLeft, valueY, valueFont, value,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                if (trend >= 0) {
                    drawTrend(dc, valueLeft + valueWidth - arrowWidth / 2 + valueHeight / 20, valueY,
                        trend, valueHeight, statusFont);
                }
                dc.setColor(statusColor, background);
                dc.drawText(x + (statusSpan[0] + statusSpan[1]) / 2,
                    y + blockTop + valueHeight + gap + statusHeight / 2, statusFont,
                    statusText == null ? statuses[statuses.size() - 1] : statusText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }
        }

        // Largest font no taller than a third of the value, or the smallest one.
        private function statusFontFor(valueHeight as Lang.Number) as Graphics.FontType {
            for (var i = 0; i < mFonts.size(); i += 1) {
                if (Graphics.getFontHeight(mFonts[i]) * 0.78 <= valueHeight * 0.34) { return mFonts[i]; }
            }
            return mFonts[mFonts.size() - 1];
        }

        private function fitting(dc as Graphics.Dc, candidates as Lang.Array<Lang.String>,
                font as Graphics.FontType, available as Lang.Number) as Lang.String? {
            for (var i = 0; i < candidates.size(); i += 1) {
                if (dc.getTextWidthInPixels(candidates[i], font) <= available) { return candidates[i]; }
            }
            return null;
        }

        // The horizontal part of a band [top, bottom) that the round screen shows,
        // in field coordinates. The narrowest row of the band decides.
        private function visibleSpan(top as Lang.Number, bottom as Lang.Number, width as Lang.Number,
                screenX as Lang.Number, screenY as Lang.Number) as Lang.Array<Lang.Number> {
            if (!mRound) { return [0, width] as Lang.Array<Lang.Number>; }
            var radius = mScreenWidth / 2.0;
            var centerY = mScreenHeight / 2.0;
            var distance = abs(screenY + top - centerY);
            var other = abs(screenY + bottom - centerY);
            if (other > distance) { distance = other; }
            if (distance >= radius) { return [0, 0] as Lang.Array<Lang.Number>; }
            var half = Math.sqrt(radius * radius - distance * distance);
            var from = (radius - half - screenX).toNumber();
            var to = (radius + half - screenX).toNumber();
            return [max(0, from), min(width, to)] as Lang.Array<Lang.Number>;
        }

        private function trendWidth(dc as Graphics.Dc, trend as Lang.Number, valueHeight as Lang.Number,
                statusFont as Graphics.FontType) as Lang.Number {
            if (trend < 0) { return 0; }
            if (trend == 0) { return dc.getTextWidthInPixels("?", statusFont) + valueHeight / 6; }
            return (valueHeight * (trend == 1 || trend == 7 ? 0.75 : 0.55)).toNumber();
        }

        // Geometric arrows, because the firmware fonts do not guarantee arrow glyphs.
        // Unknown trend is a question mark, never the steady arrow.
        private function drawTrend(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, trend as Lang.Number,
                valueHeight as Lang.Number, statusFont as Graphics.FontType) as Void {
            if (trend == 0) {
                dc.drawText(x, y, statusFont, "?", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }
            var size = max(4, valueHeight / 5);
            var dx = 0;
            var dy = trend <= 3 ? 1 : -1;
            if (trend == 3 || trend == 5) { dx = 1; }
            if (trend == 4) { dx = 1; dy = 0; }
            dc.setPenWidth(max(2, size / 4));
            if (trend == 1 || trend == 7) {
                // Far enough apart that the two heads do not touch.
                arrowLine(dc, x - size * 3 / 4, y, dx, dy, size);
                arrowLine(dc, x + size * 3 / 4, y, dx, dy, size);
            } else {
                arrowLine(dc, x, y, dx, dy, size);
            }
            dc.setPenWidth(1);
        }

        private function arrowLine(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                dx as Lang.Number, dy as Lang.Number, size as Lang.Number) as Void {
            var tipX = x + dx * size;
            var tipY = y + dy * size;
            var back = size * 2 / 3;
            var side = size / 2;
            dc.drawLine(x - dx * size, y - dy * size, tipX, tipY);
            dc.drawLine(tipX, tipY, tipX - dx * back - dy * side, tipY - dy * back + dx * side);
            dc.drawLine(tipX, tipY, tipX - dx * back + dy * side, tipY - dy * back - dx * side);
        }

        private function max(a as Lang.Number, b as Lang.Number) as Lang.Number { return a > b ? a : b; }
        private function min(a as Lang.Number, b as Lang.Number) as Lang.Number { return a < b ? a : b; }
        private function abs(a as Lang.Float or Lang.Double) as Lang.Float or Lang.Double { return a < 0 ? -a : a; }
    }
}
