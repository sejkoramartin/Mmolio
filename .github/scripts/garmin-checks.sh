#!/usr/bin/env bash
#
# Everything about the Garmin project that can be verified without the Connect IQ
# compiler. Kept as a script so it runs identically in either workflow and can be run
# locally before pushing — which is cheaper than finding out from CI.
#
set -euo pipefail

root=garmin/MedProbeWatch

echo "=== project structure ==="
for required in \
  "$root/manifest.xml" \
  "$root/monkey.jungle" \
  "$root/source/MedProbeApp.mc" \
  "$root/source/GlucoseReading.mc" \
  "$root/source/GlucoseStore.mc" \
  "$root/source/Formatter.mc" \
  "$root/source/MedProbeFaceView.mc" \
  "$root/resources/properties.xml" \
  "$root/resources-fr255/layouts.xml" \
  "$root/resources-fr165/layouts.xml"; do
  test -f "$required" || { echo "::error::missing $required"; exit 1; }
done
echo "OK: every expected file is present."

echo
echo "=== XML well-formedness ==="
python3 - <<'PYEOF'
import glob, sys, xml.etree.ElementTree as ET
failed = False
for path in sorted(glob.glob("garmin/MedProbeWatch/**/*.xml", recursive=True)):
    try:
        ET.parse(path)
        print(f"  ok   {path}")
    except ET.ParseError as error:
        print(f"  FAIL {path}: {error}")
        failed = True
sys.exit(1 if failed else 0)
PYEOF

echo
echo "=== both target devices declared ==="
for device in fr255 fr165; do
  grep -q "id=\"$device\"" "$root/manifest.xml" || {
    echo "::error::$device is not in the manifest"; exit 1; }
  grep -q "^$device\." "$root/monkey.jungle" || {
    echo "::error::$device has no resource path in monkey.jungle"; exit 1; }
done
echo "OK: fr255 and fr165 are declared with their own resources."

echo
echo "=== wire protocol matches the phone ==="
SWIFT=MedProbe/Garmin/GarminMessage.swift
MONKEY="$root/source/GlucoseReading.mc"

swift_version=$(grep -oE 'currentVersion = [0-9]+' "$SWIFT" | grep -oE '[0-9]+')
monkey_version=$(grep -oE 'SUPPORTED_VERSION = [0-9]+' "$MONKEY" | grep -oE '[0-9]+')
echo "protocol version: Swift=$swift_version MonkeyC=$monkey_version"
[ "$swift_version" = "$monkey_version" ] || {
  echo "::error::Protocol version differs between phone and watch"; exit 1; }

for pair in 'version:v' 'mgdl:g' 'trend:t' 'measuredAt:m' 'source:s' 'sequence:q'; do
  name=${pair%%:*}
  key=${pair##*:}
  grep -q "static let $name = \"$key\"" "$SWIFT" || {
    echo "::error::Swift key for $name is not \"$key\""; exit 1; }
  grep -qE "KEY_[A-Z_]+ = \"$key\"" "$MONKEY" || {
    echo "::error::Monkey C is missing the key \"$key\""; exit 1; }
done
echo "OK: both sides agree on the wire format."

echo
echo "=== staleness is handled wherever a value is drawn ==="
grep -q "function isStale" "$MONKEY" || {
  echo "::error::GlucoseReading has no isStale"; exit 1; }
for view in MedProbeFaceView MedProbeView; do
  grep -q "isStale" "$root/source/$view.mc" || {
    echo "::error::$view does not check staleness"; exit 1; }
done
echo "OK: staleness is checked wherever a value is drawn."
