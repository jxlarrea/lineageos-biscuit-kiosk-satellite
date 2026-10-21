#!/usr/bin/env bash
# Compile the real renderer on the host and verify the public countdown contract.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(TMPDIR=/tmp mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

"${CXX:-g++}" -std=gnu++11 -Wall -Werror -pthread \
    "$REPO_ROOT/tests/test-led-countdown.cpp" -o "$TMPDIR/test-led-countdown"
"$TMPDIR/test-led-countdown"
bash -n "$REPO_ROOT/device/amazon/biscuit/biscuit-service/biscuit_service"
grep -Fq 'com.amazon.biscuit.service.COUNTDOWN_PROGRESS' \
    "$REPO_ROOT/device/amazon/biscuit/biscuit-service/service/AndroidManifest.xml"
grep -Fq '!strncmp(line, "COUNTDOWN ", 10)' \
    "$REPO_ROOT/device/amazon/biscuit/biscuit-service/biscuit-ledd.cpp"
grep -Fq "adb shell biscuit_service countdown set '<remaining-ms>' '<total-ms>'" "$REPO_ROOT/docs/device-commands.md"

echo 'PASS countdown renderer and public contract'
