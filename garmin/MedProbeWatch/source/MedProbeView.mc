//
// MedProbeView.mc
//
// The in-app screen: the same information the watch face shows, for checking that
// messages are arriving.
//
// Layout comes from device-specific resources, so fr255 and fr165 differ in geometry
// rather than in code.
//

using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Timer;

module MedProbe {

    class MedProbeView extends WatchUi.View {

        var mRefreshTimer;

        function initialize() {
            View.initialize();
        }

        function onShow() as Void {
            mRefreshTimer = new Timer.Timer();
            mRefreshTimer.start(method(:refresh), 30000, true);
        }

        function onHide() as Void {
            if (mRefreshTimer != null) { mRefreshTimer.stop(); mRefreshTimer = null; }
        }

        function refresh() as Void { WatchUi.requestUpdate(); }

        function onLayout(dc) {
            setLayout(Rez.Layouts.MainLayout(dc));
        }

        function onUpdate(dc) {
            var reading = GlucoseStore.load();
            var isStale = reading != null && reading.isStale(GlucoseStore.staleThresholdSeconds());

            var valueLabel = View.findDrawableById("glucoseValue") as WatchUi.Text?;
            var arrowLabel = View.findDrawableById("trendArrow") as WatchUi.Text?;
            var unitLabel = View.findDrawableById("unit") as WatchUi.Text?;
            var ageLabel = View.findDrawableById("age") as WatchUi.Text?;

            if (valueLabel != null) {
                valueLabel.setText(Formatter.value(reading));
                // Stale values are dimmed as well as labelled, so the state is obvious
                // without reading the age.
                valueLabel.setColor(isStale ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_WHITE);
            }
            if (arrowLabel != null) {
                // A stale reading's trend is not shown at all: direction from an old
                // value is worse than no direction.
                arrowLabel.setText(isStale ? "" : Formatter.arrow(reading));
            }
            if (unitLabel != null) {
                unitLabel.setText(Formatter.unitLabel());
            }
            if (ageLabel != null) {
                ageLabel.setText(reading == null ? "NO DATA" : (isStale ? "STALE " : "") + Formatter.age(reading));
                ageLabel.setColor(isStale ? Graphics.COLOR_ORANGE : Graphics.COLOR_LT_GRAY);
            }
            View.onUpdate(dc);
        }
    }
}
