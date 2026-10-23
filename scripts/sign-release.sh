#!/usr/bin/env bash
# Sign a release zip for system updates: writes <zip>.sig, a SHA256withRSA
# signature that BiscuitService checks against the public key in
# device/amazon/biscuit/biscuit-service/ota/release-key.pem before it installs
# the zip. A release without the .sig is only installed by hand.
#
# The private key stays outside the repository, in
# ~/.config/biscuit-ota/release-key.pem unless BISCUIT_OTA_KEY says otherwise.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${BISCUIT_OTA_KEY:-$HOME/.config/biscuit-ota/release-key.pem}"
PUBLIC="$REPO_ROOT/device/amazon/biscuit/biscuit-service/ota/release-key.pem"

[[ $# -eq 1 && -f "$1" ]] || { echo "usage: $0 <release.zip>" >&2; exit 2; }
[[ -f "$KEY" ]] || { echo "ERROR: no private key at $KEY (set BISCUIT_OTA_KEY)" >&2; exit 1; }

ZIP="$1"
openssl dgst -sha256 -sign "$KEY" -out "$ZIP.sig" "$ZIP"
# Check it the way the Dot will, with the key the image ships.
openssl dgst -sha256 -verify "$PUBLIC" -signature "$ZIP.sig" "$ZIP"
echo "Wrote $ZIP.sig"
