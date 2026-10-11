#!/usr/bin/env bash
# Backwards-compatible FR165 entry point.
set -euo pipefail
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/build-device.sh" fr165 "$@"
