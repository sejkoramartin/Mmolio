using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Test;

// Helpers live in an annotated module: excluded from release, and not run as tests.
// Tests that store a reading delete it again: the simulator shares storage with the app.
(:test)
module FieldTestSupport {
    function packet(g, t, m, s, q) as Lang.Dictionary {
        return {"v" => 1, "g" => g, "t" => t, "m" => m, "s" => s, "q" => q};
    }

    function stored() {
        return MedProbe.GlucoseStore.load();
    }
}

(:test)
function fieldShowsNoDataBeforeFirstReading(logger as Test.Logger) as Lang.Boolean {
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    Test.assert(FieldTestSupport.stored() == null);
    Test.assert(MmolioField.FieldReceiver.toSample(null, true, 900) == null);
    return true;
}

(:test)
function fieldAcceptsV1PacketAndKeepsMeasurementTimeAcrossRestart(logger as Test.Logger) as Lang.Boolean {
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    Test.assert(MmolioField.FieldReceiver.receive(FieldTestSupport.packet(115, 5, 1700000000, 3, 10)));
    // A restarted field has only storage; the measurement time must survive, not receipt time.
    var sample = MmolioField.FieldReceiver.toSample(FieldTestSupport.stored(), true, 900);
    Test.assertEqual(1700000000l, sample.measuredAt);
    Test.assertEqual("6.4", sample.valueText());
    Test.assertEqual("mmol/L", sample.unitText());
    Test.assertEqual(5, sample.trend);
    Test.assert(!sample.isStale(1700000899));
    Test.assertEqual("14m", sample.ageText(1700000899));
    Test.assert(sample.isStale(1700000900));
    Test.assertEqual("STALE 15m", sample.ageText(1700000900));
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    return true;
}

(:test)
function fieldRefusesDuplicateAndOlderPacketsLikeBridge(logger as Test.Logger) as Lang.Boolean {
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    Test.assert(MmolioField.FieldReceiver.receive(FieldTestSupport.packet(115, 4, 1700000000, 3, 10)));
    Test.assert(!MmolioField.FieldReceiver.receive(FieldTestSupport.packet(115, 4, 1700000000, 3, 10)));
    Test.assert(!MmolioField.FieldReceiver.receive(FieldTestSupport.packet(140, 6, 1700000300, 3, 9)));
    Test.assert(!MmolioField.FieldReceiver.receive(FieldTestSupport.packet(140, 6, 1699999700, 3, 11)));
    Test.assertEqual(1700000000l, FieldTestSupport.stored().measuredAt.toLong());
    Test.assert(MmolioField.FieldReceiver.receive(FieldTestSupport.packet(140, 6, 1700000300, 3, 11)));
    Test.assertEqual(140, FieldTestSupport.stored().mgdl);
    // Sequences are only comparable within one source, as in Bridge.
    Test.assert(MmolioField.FieldReceiver.receive(FieldTestSupport.packet(120, 4, 1700000600, 2, 1)));
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    return true;
}

(:test)
function fieldRejectsInvalidPacketsAndKeepsLastValid(logger as Test.Logger) as Lang.Boolean {
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    Test.assert(MmolioField.FieldReceiver.receive(FieldTestSupport.packet(115, 4, 1700000000, 3, 10)));
    var invalid = [
        null, 115, "1|115|4|1700000000|1|900", [1, 115],
        {"v" => 2, "g" => 115, "t" => 4, "m" => 1700000300, "s" => 3, "q" => 11},
        {"v" => 1, "g" => 115, "t" => 4, "m" => 1700000300, "s" => 3},
        FieldTestSupport.packet("115", 4, 1700000300, 3, 11), FieldTestSupport.packet(115.0, 4, 1700000300, 3, 11),
        FieldTestSupport.packet(0, 4, 1700000300, 3, 11), FieldTestSupport.packet(1001, 4, 1700000300, 3, 11),
        FieldTestSupport.packet(115, 8, 1700000300, 3, 11), FieldTestSupport.packet(115, -1, 1700000300, 3, 11),
        FieldTestSupport.packet(115, 4, 0, 3, 11), FieldTestSupport.packet(115, 4, -5, 3, 11),
        FieldTestSupport.packet(115, 4, 1700000300, "3", 11), FieldTestSupport.packet(115, 4, 1700000300, 3, true)];
    for (var i = 0; i < invalid.size(); i += 1) {
        Test.assertMessage(!MmolioField.FieldReceiver.receive(invalid[i]),
            "Must reject invalid packet index " + i);
    }
    var kept = FieldTestSupport.stored();
    Test.assertEqual(115, kept.mgdl);
    Test.assertEqual(1700000000l, kept.measuredAt.toLong());
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    return true;
}

(:test)
function fieldFutureMeasurementIsCheckTime(logger as Test.Logger) as Lang.Boolean {
    var reading = new MedProbe.GlucoseReading(115, 6, 1700000600, 3, 1);
    var sample = MmolioField.FieldReceiver.toSample(reading, true, 900);
    Test.assert(sample.isStale(1700000599));
    Test.assertEqual("CHECK TIME", sample.ageText(1700000599));
    Test.assert(!sample.isStale(1700000600));
    return true;
}

(:test)
function fieldUnitsLimitsAndFourDigitValue(logger as Test.Logger) as Lang.Boolean {
    var reading = new MedProbe.GlucoseReading(115, 0, 1700000000, 3, 1);
    var mgdl = MmolioField.FieldReceiver.toSample(reading, false, 300);
    Test.assertEqual("115", mgdl.valueText());
    Test.assertEqual("mg/dL", mgdl.unitText());
    Test.assertEqual(0, mgdl.trend);
    Test.assertEqual("4m", mgdl.ageText(1700000299));
    Test.assertEqual("STALE 5m", mgdl.ageText(1700000300));
    Test.assertEqual("STALE 1h12m", mgdl.ageText(1700004320));
    var high = MmolioField.FieldReceiver.toSample(new MedProbe.GlucoseReading(1000, 7, 1700000000, 3, 2), false, 900);
    Test.assertEqual("1000", high.valueText());
    Test.assertEqual("55.5", MmolioField.FieldReceiver.toSample(new MedProbe.GlucoseReading(1000, 7, 1700000000, 3, 2), true, 900).valueText());
    // Timestamps beyond 32-bit signed seconds stay exact.
    var late = MmolioField.FieldReceiver.toSample(new MedProbe.GlucoseReading(115, 4, 2200000000l, 3, 3), true, 7200);
    Test.assert(!late.isStale(2200007199l));
    Test.assert(late.isStale(2200007200l));
    return true;
}

(:test)
function fieldSettingsAreItsOwnAndValidated(logger as Test.Logger) as Lang.Boolean {
    var originalMinutes = Application.Properties.getValue("staleMinutes");
    var originalMmol = Application.Properties.getValue("useMmol");
    Test.assertEqual(15, originalMinutes);
    Test.assertEqual(true, originalMmol);
    Test.assertEqual(900, MedProbe.GlucoseStore.staleThresholdSeconds());
    Application.Properties.setValue("staleMinutes", 5);
    Test.assertEqual(300, MedProbe.GlucoseStore.staleThresholdSeconds());
    Application.Properties.setValue("staleMinutes", 120);
    Test.assertEqual(7200, MedProbe.GlucoseStore.staleThresholdSeconds());
    Application.Properties.setValue("staleMinutes", 4);
    Test.assertEqual(900, MedProbe.GlucoseStore.staleThresholdSeconds());
    Application.Properties.setValue("staleMinutes", 121);
    Test.assertEqual(900, MedProbe.GlucoseStore.staleThresholdSeconds());
    Application.Properties.setValue("useMmol", false);
    Test.assert(!MmolioField.FieldReceiver.usesMmol());
    Application.Properties.setValue("staleMinutes", originalMinutes);
    Application.Properties.setValue("useMmol", originalMmol);
    Test.assert(MmolioField.FieldReceiver.usesMmol());
    return true;
}

(:test)
function fieldFollowsPhoneUnitsAndLegacyFallback(logger as Test.Logger) as Lang.Boolean {
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    var oldSetting = Application.Properties.getValue("useMmol");
    Application.Properties.setValue("useMmol", false);
    var packet = FieldTestSupport.packet(180, 4, 1700000000, 3, 100);
    packet["u"] = 1;
    Test.assert(MmolioField.FieldReceiver.receive(packet));
    Test.assert(MmolioField.FieldReceiver.usesMmol());
    var sample = MmolioField.FieldReceiver.toSample(FieldTestSupport.stored(), MmolioField.FieldReceiver.usesMmol(), 900);
    Test.assertEqual("10.0", sample.valueText());
    Test.assertEqual("mmol/L", sample.unitText());
    packet["u"] = 0; packet["q"] = 101;
    Test.assert(MmolioField.FieldReceiver.receive(packet));
    sample = MmolioField.FieldReceiver.toSample(FieldTestSupport.stored(), MmolioField.FieldReceiver.usesMmol(), 900);
    Test.assertEqual("180", sample.valueText());
    Test.assertEqual("mg/dL", sample.unitText());
    Test.assert(sample.isStale(1700000900));
    packet["u"] = 1; packet["q"] = 100;
    Test.assert(!MmolioField.FieldReceiver.receive(packet));
    Test.assert(!MmolioField.FieldReceiver.usesMmol());
    packet["q"] = 102; packet["u"] = 2;
    Test.assert(!MmolioField.FieldReceiver.receive(packet));
    Application.Properties.setValue("useMmol", true);
    Test.assert(MmolioField.FieldReceiver.receive(FieldTestSupport.packet(180, 4, 1700000000, 3, 103)));
    Test.assert(MmolioField.FieldReceiver.usesMmol());
    Storage.deleteValue(MedProbe.GlucoseStore.STORAGE_KEY);
    Application.Properties.setValue("useMmol", oldSetting);
    return true;
}
