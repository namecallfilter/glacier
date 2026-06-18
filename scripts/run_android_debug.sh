#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-49200DLAQ001HG}"

adb -s "$DEVICE" shell setprop log.tag.r.glacier.debug S
adb -s "$DEVICE" shell am force-stop com.namecallfilter.glacier.debug || true

flutter run -d "$DEVICE" --dart-define-from-file=.env
