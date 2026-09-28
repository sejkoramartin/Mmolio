using Toybox.Test;

(:test)
function sampleFreshnessBoundary(logger) {
    var sample = Mmolio.SampleCodec.decode("2|115|5|1700000000|1|900|76|171");
    Test.assert(sample != null);
    Test.assert(!sample.isStale(1700000899));
    Test.assert(sample.isStale(1700000900));
    Test.assert(sample.isStale(1700000901));
    Test.assertEqual("STALE 15m", sample.ageText(1700000900));
    return true;
}

(:test)
function sampleDoesNotRejuvenateOnRedelivery(logger) {
    var first = Mmolio.SampleCodec.decode("2|115|4|1700000000|1|900|76|171");
    var redelivered = Mmolio.SampleCodec.decode("2|115|4|1700000000|1|900|76|171");
    Test.assert(first.isStale(1700001000));
    Test.assert(redelivered.isStale(1700001000));
    // A different value with the same timestamp must be just as old.
    var changed = Mmolio.SampleCodec.decode("2|140|6|1700000000|1|900|76|171");
    Test.assert(changed.isStale(1700001000));
    return true;
}

(:test)
function sampleFutureClockIsUntrusted(logger) {
    var sample = Mmolio.SampleCodec.decode("2|115|4|1700000000|1|900|76|171");
    Test.assert(sample.isStale(1699999999));
    Test.assertEqual("CHECK TIME", sample.ageText(1699999999));
    Test.assert(!sample.isStale(1700000000));
    Test.assertEqual("<1m", sample.ageText(1700000000));
    return true;
}

(:test)
function sampleRejectsMissingLegacyAndMalformed(logger) {
    var invalid = [null, 115, "", "6.4 →", "1|115|4|1700000000|1",
        "2|115|4|1700000000|1|900", "2|115|4|1700000000|1|900|76",
        "2|115|4|1700000000|1|900|76|171|9", "2|115|4|1700000000|1|900|0|171",
        "2|115|4|1700000000|1|900|171|76", "2|115|4|1700000000|1|900|76|1001",
        "3|115|4|1700000000|1|900|76|171",
        "1|115|4|1700000000|1|900|extra", "2|115|4|1700000000|1|900",
        "1|115|4||1|900", "1|115|4|0|1|900", "1|115|4|-1|1|900",
        "1|115|4|1700000000x|1|900", "1|115|4|1700000000|1|900x",
        "1|115|4|1700000000|1|900.0", "1|115|4|1700000000|1|0900",
        "1|115|4|1700000000|2|900", "1|115|8|1700000000|1|900",
        "1|0|4|1700000000|1|900", "1|1001|4|1700000000|1|900",
        "1|115|4|1700000000|1|299", "1|115|4|1700000000|1|7201",
        "1|115|4|999999999999999999999999|1|900"];
    for (var i = 0; i < invalid.size(); i += 1) {
        Test.assertMessage(Mmolio.SampleCodec.decode(invalid[i]) == null,
            "Must reject malformed sample index " + i);
    }
    return true;
}

(:test)
function sampleUnitsAgeAndLongTimestamp(logger) {
    var mmol = Mmolio.SampleCodec.decode("2|115|0|1700000000|1|300|76|171");
    Test.assertEqual("6.4", mmol.valueText());
    Test.assertEqual("mmol/L", mmol.unitText());
    Test.assertEqual(0, mmol.trend);
    Test.assertEqual("4m", mmol.ageText(1700000299));
    Test.assertEqual("STALE 5m", mmol.ageText(1700000300));
    Test.assertEqual("STALE 1h12m", mmol.ageText(1700004320));
    Test.assertEqual("STALE 2d", mmol.ageText(1700172800));
    var mgdl = Mmolio.SampleCodec.decode("2|115|7|2200000000|0|7200|76|171");
    Test.assertEqual("115", mgdl.valueText());
    Test.assertEqual("mg/dL", mgdl.unitText());
    Test.assert(!mgdl.isStale(2200007199l));
    Test.assert(mgdl.isStale(2200007200l));
    return true;
}

(:test)
function sampleV1PayloadStillWorksWithDefaultLimits(logger) {
    // An older Bridge sends no limits; the face must still show the reading.
    var sample = Mmolio.SampleCodec.decode("1|115|5|1700000000|1|900");
    Test.assert(sample != null);
    Test.assertEqual(115, sample.mgdl);
    Test.assertEqual(Mmolio.SampleCodec.DEFAULT_LOW_MGDL, sample.lowMgdl);
    Test.assertEqual(Mmolio.SampleCodec.DEFAULT_HIGH_MGDL, sample.highMgdl);
    Test.assert(sample.inRange());
    return true;
}

(:test)
function sampleRangeFollowsThePublishedLimits(logger) {
    var sample = Mmolio.SampleCodec.decode("2|115|5|1700000000|1|900|76|171");
    Test.assert(sample.inRange());
    Test.assert(Mmolio.SampleCodec.decode("2|76|5|1700000000|1|900|76|171").inRange());
    Test.assert(Mmolio.SampleCodec.decode("2|171|5|1700000000|1|900|76|171").inRange());
    Test.assert(!Mmolio.SampleCodec.decode("2|75|5|1700000000|1|900|76|171").inRange());
    Test.assert(!Mmolio.SampleCodec.decode("2|172|5|1700000000|1|900|76|171").inRange());
    // Tighter limits from the settings move the boundary with them.
    Test.assert(!Mmolio.SampleCodec.decode("2|115|5|1700000000|1|900|90|108").inRange());
    return true;
}
