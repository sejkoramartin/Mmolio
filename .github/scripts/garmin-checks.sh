#!/usr/bin/env bash
#
# Everything about the Garmin project that can be verified without the Connect IQ
# compiler. Kept as a script so it runs identically in either workflow and can be run
# locally before pushing — which is cheaper than finding out from CI.
#
set -euo pipefail

root=garmin/MmolioBridge
face=garmin/MmolioWatchFace
field=garmin/MmolioDataField

echo "=== project structure ==="
for required in \
  "$root/manifest.xml" \
  "$root/monkey.jungle" \
  "$root/source/MedProbeApp.mc" \
  "$root/source/GlucoseReading.mc" \
  "$root/source/GlucoseStore.mc" \
  "$root/source/Formatter.mc" \
  "$root/resources/properties.xml" \
  "$root/resources-fr255/layouts.xml" \
  "$root/resources-fr165/layouts.xml"; do
  test -f "$required" || { echo "::error::missing $required"; exit 1; }
done
for required in \
  "$face/manifest.xml" \
  "$face/monkey.jungle" \
  "$face/source/xDripWatchFaceApp.mc" \
  "$face/source/xDripWatchFaceView.mc" \
  "$face/resources/strings.xml" \
  "$face/resources/drawables.xml"; do
  test -f "$required" || { echo "::error::missing $required"; exit 1; }
done
for required in \
  "$field/manifest.xml" \
  "$field/monkey.jungle" \
  "$field/source/MmolioDataFieldApp.mc" \
  "$field/source/MmolioDataFieldView.mc" \
  "$field/source/FieldReceiver.mc" \
  "$field/source/FieldRenderer.mc" \
  "$field/resources/properties.xml" \
  "$field/resources/settings.xml" \
  "$field/resources/strings.xml"; do
  test -f "$required" || { echo "::error::missing $required"; exit 1; }
done
echo "OK: every expected file is present."

echo
echo "=== application identities ==="
# The phone addresses each app by these IDs; changing one silently cuts it off.
python3 - <<'PYEOF'
import sys, xml.etree.ElementTree as ET
ns = {"iq": "http://www.garmin.com/xml/connectiq"}
expected = {
    "garmin/MmolioBridge/manifest.xml": ("a1b2c3d4e5f647589a0b1c2d3e4f5061", "watch-app", None),
    "garmin/MmolioWatchFace/manifest.xml": ("b1c2d3e4f5a647589a0b1c2d3e4f5072", "watchface", None),
    "garmin/MmolioDataField/manifest.xml": ("7ca56fd800634cab90f28d5e72be2e05", "datafield", "5.0.0"),
}
failed = False
for path, (app_id, app_type, min_api) in expected.items():
    app = ET.parse(path).getroot().find("iq:application", ns)
    actual = (app.get("id"), app.get("type"))
    if actual != (app_id, app_type) or (min_api and app.get("minApiLevel") != min_api):
        print(f"::error::{path} has id/type/minApiLevel {actual + (app.get('minApiLevel'),)}")
        failed = True
    else:
        print(f"  ok   {path}: {app_type} {app_id}")
field = ET.parse("garmin/MmolioDataField/manifest.xml").getroot().find("iq:application", ns)
permissions = {p.get("id") for p in field.iter("{%s}uses-permission" % ns["iq"])}
# Data fields may not subscribe to complications; the field must receive phone messages.
if "Communications" not in permissions or permissions & {"ComplicationSubscriber", "ComplicationPublisher"}:
    print(f"::error::Mmolio DataField permissions are {sorted(permissions)}")
    failed = True
sys.exit(1 if failed else 0)
PYEOF
echo "OK: application identities are unchanged."

echo
echo "=== XML well-formedness ==="
python3 - <<'PYEOF'
import glob, sys, xml.etree.ElementTree as ET
failed = False
for path in sorted(glob.glob("garmin/**/*.xml", recursive=True)):
    try:
        ET.parse(path)
        print(f"  ok   {path}")
    except ET.ParseError as error:
        print(f"  FAIL {path}: {error}")
        failed = True
sys.exit(1 if failed else 0)
PYEOF

echo
echo "=== declared devices resolve to resources ==="
# Every product in the manifest must have a jungle resource path, or the build fails at
# a point that is hard to read. fr255 is present as resources but commented out in both
# files until its SDK definition is fetched — see README.
for device in $(grep -oE '<iq:product id="[a-z0-9]+"' "$root/manifest.xml" | sed 's/.*id="//;s/"//'); do
  grep -qE "^$device\." "$root/monkey.jungle" || {
    echo "::error::$device is in the manifest but has no resource path in monkey.jungle"; exit 1; }
done
test -d "$root/resources-fr255" || { echo "::error::fr255 resources missing"; exit 1; }
test -d "$root/resources-fr165" || { echo "::error::fr165 resources missing"; exit 1; }
echo "OK: every declared device resolves, and resources for both targets exist."

echo
echo "=== wire protocol matches the contract ==="
# The sender lives in the xDrip4iOS fork, so the contract itself is the reference here.
CONTRACT=garmin/wire-protocol.md
MONKEY="$root/source/GlucoseReading.mc"

contract_version=$(grep -oE '^ +version = [0-9]+' "$CONTRACT" | grep -oE '[0-9]+')
monkey_version=$(grep -oE 'SUPPORTED_VERSION = [0-9]+' "$MONKEY" | grep -oE '[0-9]+')
echo "protocol version: contract=$contract_version MonkeyC=$monkey_version"
[ "$contract_version" = "$monkey_version" ] || {
  echo "::error::Protocol version differs between the contract and the watch"; exit 1; }

for key in v g t m s q; do
  grep -qE "^\| \`$key\` \|" "$CONTRACT" || {
    echo "::error::The contract does not define the key \"$key\""; exit 1; }
  grep -qE "KEY_[A-Z_]+ = \"$key\"" "$MONKEY" || {
    echo "::error::Monkey C is missing the key \"$key\""; exit 1; }
done
# Mmolio DataField must parse the phone packet with Bridge's own files, not a copy.
for shared in GlucoseReading GlucoseStore; do
  grep -q "\.\./MmolioBridge/source/$shared.mc" "$field/monkey.jungle" || {
    echo "::error::Mmolio DataField does not compile Bridge's $shared.mc"; exit 1; }
  test ! -e "$field/source/$shared.mc" || {
    echo "::error::Mmolio DataField has its own copy of $shared.mc"; exit 1; }
done
echo "OK: both sides agree on the wire format."

echo
echo "=== staleness is handled wherever a value is drawn ==="
grep -q "function isStale" "$MONKEY" || {
  echo "::error::GlucoseReading has no isStale"; exit 1; }
for view in MedProbeView; do
  grep -q "isStale" "$root/source/$view.mc" || {
    echo "::error::$view does not check staleness"; exit 1; }
done
grep -q "isStale" "$field/source/FieldRenderer.mc" || {
  echo "::error::Mmolio DataField does not check staleness"; exit 1; }
echo "OK: staleness is checked wherever a value is drawn."
