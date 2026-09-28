using Toybox.Test;
using Toybox.Time;

(:test)
function publisherRoundTripKeepsMeasurementAndSettings(logger) {
    for (var trend = 0; trend <= 7; trend += 1) {
        var reading = new MedProbe.GlucoseReading(115, trend, 1700000000, 3, 42);
        var wire = MedProbe.GlucoseComplication.encodeSample(reading, true, 900);
        var decoded = Mmolio.SampleCodec.decode(wire);
        Test.assert(decoded != null);
        Test.assertEqual(115, decoded.mgdl);
        Test.assertEqual(trend, decoded.trend);
        Test.assertEqual(1700000000l, decoded.measuredAt);
        Test.assert(decoded.useMmol);
        Test.assertEqual(900, decoded.staleSeconds);
        Test.assert(decoded.isStale(1700000900));
    }
    var reading = new MedProbe.GlucoseReading(250, 4, 1700000000, 3, 43);
    var mgdl = Mmolio.SampleCodec.decode(MedProbe.GlucoseComplication.encodeSample(reading, false, 300));
    Test.assertEqual("250", mgdl.valueText());
    Test.assertEqual("mg/dL", mgdl.unitText());
    Test.assert(mgdl.isStale(1700000300));
    return true;
}

(:test)
function originalPhonePacketAndOrderingRemainCompatible(logger) {
    var packet = {"v" => 1, "g" => 115, "t" => 5, "m" => 1700000000, "s" => 3, "q" => 42};
    var reading = MedProbe.GlucoseReading.fromMessage(packet);
    Test.assert(reading != null);
    Test.assertEqual(115, reading.mgdl);
    Test.assertEqual(1700000000, reading.measuredAt);
    Test.assert(!reading.isNewerThan(reading));
    var older = new MedProbe.GlucoseReading(130, 4, 1699999999, 3, 41);
    Test.assert(reading.isNewerThan(older));
    Test.assert(!older.isNewerThan(reading));
    var restored = MedProbe.GlucoseReading.fromStorage(reading.toStorage());
    Test.assertEqual(reading.measuredAt, restored.measuredAt);
    packet["v"] = 2;
    Test.assert(MedProbe.GlucoseReading.fromMessage(packet) == null);
    return true;
}

(:test)
function receiverFutureTimestampIsStale(logger) {
    var future = new MedProbe.GlucoseReading(115, 4, Time.now().value() + 3600, 3, 42);
    Test.assert(future.isStale(900));
    Test.assertEqual("CHECK TIME", MedProbe.Formatter.age(future));
    return true;
}
