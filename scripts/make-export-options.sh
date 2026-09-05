#!/usr/bin/env bash
#
# Writes the ExportOptions.plist used by `xcodebuild -exportArchive`.
#
# Kept as a script rather than inlined in the workflow so that CI can generate and
# lint it with placeholder values on every push, without any Apple credentials.
#
# Usage: make-export-options.sh <team-id> <profile-name> <bundle-id> <output-path>
#
# Nothing written here is a secret: a team ID and a profile name are both visible in
# any shipped .ipa. The signing certificate and API key never come near this file.

set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <team-id> <profile-name> <bundle-id> <output-path>" >&2
    exit 2
fi

TEAM_ID="$1"
PROFILE_NAME="$2"
BUNDLE_ID="$3"
OUTPUT_PATH="$4"

# "app-store-connect" is the current method name. The older "app-store" spelling is
# deprecated in recent Xcode releases, so it is deliberately not used here.
cat > "$OUTPUT_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>

    <key>destination</key>
    <string>export</string>

    <key>teamID</key>
    <string>${TEAM_ID}</string>

    <key>signingStyle</key>
    <string>manual</string>

    <key>signingCertificate</key>
    <string>Apple Distribution</string>

    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID}</key>
        <string>${PROFILE_NAME}</string>
    </dict>

    <key>uploadSymbols</key>
    <true/>

    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST

echo "Wrote export options to ${OUTPUT_PATH}"
