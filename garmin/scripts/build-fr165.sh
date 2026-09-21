#!/usr/bin/env bash
# Usage: CONNECTIQ_SDK=/path/to/sdk DEVELOPER_KEY=/path/to/existing.der ./garmin/scripts/build-fr165.sh [--test]
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
mode=release
flags=(-r)
if [[ ${1:-} == --test ]]; then
    mode=test
    flags=(-t)
elif [[ $# != 0 ]]; then
    echo "Usage: $0 [--test]" >&2; exit 1
fi
out="$repo/build/fr165/$mode"
mkdir -p -- "$out"
cd -- "$repo"
"$sdk/bin/monkeyc" -f garmin/MedProbeWatch/monkey.jungle -d fr165 \
    -o "$out/MmolioBridge.prg" -y "$key" -l 2 "${flags[@]}"
"$sdk/bin/monkeyc" -f garmin/xDripWatchFace/monkey.jungle -d fr165 \
    -o "$out/MmolioWatchFace.prg" -y "$key" -l 2 "${flags[@]}"
printf 'Built both applications: %s\n' "$out"
if [[ $mode == test ]]; then
    printf 'With the SDK simulator running, run:\n  %q %q fr165 -t\n  %q %q fr165 -t\n' \
        "$sdk/bin/monkeydo" "$out/MmolioBridge.prg" "$sdk/bin/monkeydo" "$out/MmolioWatchFace.prg"
fi
