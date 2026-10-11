#!/usr/bin/env bash
# Usage: CONNECTIQ_SDK=/path/to/sdk DEVELOPER_KEY=/path/to/existing.der ./garmin/scripts/build-device.sh DEVICE [--test]
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
: "${CONNECTIQ_SDK:?Set CONNECTIQ_SDK to Connect IQ SDK 9.2.0}"
: "${DEVELOPER_KEY:?Set DEVELOPER_KEY to the existing Garmin developer .der key}"
sdk=$(cd -- "$CONNECTIQ_SDK" && pwd)
key=$(realpath -- "$DEVELOPER_KEY")
[[ -f "$key" ]] || { echo "Signing key not found" >&2; exit 1; }
[[ $(tr -d '\r\n' < "$sdk/bin/version.txt") == '9.2.0' ]] || {
    echo "This build is pinned to Connect IQ SDK 9.2.0" >&2; exit 1;
}
device=${1:-}
case "$device" in
    fr165|fenix7xpro|fenix7xpronowifi) shift ;;
    *) echo "Usage: $0 {fr165|fenix7xpro|fenix7xpronowifi} [--test]" >&2; exit 1 ;;
esac
mode=release
flags=(-r)
if [[ $# == 1 && ${1:-} == --test ]]; then
    mode=test
    flags=(-t)
elif [[ $# != 0 ]]; then
    echo "Usage: $0 DEVICE [--test]" >&2; exit 1
fi
out="$repo/build/$device/$mode"
mkdir -p -- "$out"
cd -- "$repo"
"$sdk/bin/monkeyc" -f garmin/MmolioBridge/monkey.jungle -d "$device" \
    -o "$out/MmolioBridge.prg" -y "$key" -l 2 "${flags[@]}"
"$sdk/bin/monkeyc" -f garmin/MmolioWatchFace/monkey.jungle -d "$device" \
    -o "$out/MmolioWatchFace.prg" -y "$key" -l 2 "${flags[@]}"
"$sdk/bin/monkeyc" -f garmin/MmolioDataField/monkey.jungle -d "$device" \
    -o "$out/MmolioDataField.prg" -y "$key" -l 2 "${flags[@]}"
printf 'Built all three applications: %s\n' "$out"
if [[ $mode == test ]]; then
    printf 'With the SDK simulator running, run:\n'
    for app in MmolioBridge MmolioWatchFace MmolioDataField; do
        printf '  %q %q %q -t\n' "$sdk/bin/monkeydo" "$out/$app.prg" "$device"
    done
fi
