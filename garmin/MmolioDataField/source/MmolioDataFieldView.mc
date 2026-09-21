using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.WatchUi;

module MmolioField {

    class MmolioDataFieldView extends WatchUi.DataField {

        var mRenderer as FieldRenderer? = null;

        function initialize() {
            DataField.initialize();
        }

        // The field shows the phone reading only; activity data is not used.
        function compute(info as Activity.Info) as Void {
        }

        function onLayout(dc as Graphics.Dc) as Void {
            if (mRenderer == null) { mRenderer = new FieldRenderer(); }
        }

        function onUpdate(dc as Graphics.Dc) as Void {
            if (mRenderer == null) { mRenderer = new FieldRenderer(); }
            // Follows the activity theme: black or white background with matching colours.
            (mRenderer as FieldRenderer).draw(dc, 0, 0, dc.getWidth(), dc.getHeight(),
                getObscurityFlags(), getBackgroundColor() != Graphics.COLOR_WHITE,
                Time.now().value(), getApp().currentSample());
        }
    }
}
