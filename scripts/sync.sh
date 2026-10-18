#!/usr/bin/env bash
# Sync CM14.1 and create a resolved lock manifest on the first successful sync.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The checkout, downloads and build output: tens of GB, so it can live
# outside the repository (BISCUIT_WORKSPACE).
WORKSPACE_DIR="${BISCUIT_WORKSPACE:-$REPO_ROOT/workspace}"
CM14="${CM14:-$WORKSPACE_DIR/cm14.1}"
LOCAL_MANIFEST="$REPO_ROOT/manifest/local.xml"
LOCK="$REPO_ROOT/manifest/lock.xml"
REPO_BIN="${REPO_BIN:-}"
WEBVIEW_DIR="$CM14/external/chromium-webview/prebuilt/arm"
WEBVIEW_APK="$WEBVIEW_DIR/webview.apk"
WEBVIEW_APK_SHA256="feeedd44677f5643e2de2de4a44061f7bd31a662e78909d6e052b4fe1468870a"
WEBVIEW_APK_SIZE=83580708

[[ -f "$LOCAL_MANIFEST" ]] || { echo "ERROR: missing $LOCAL_MANIFEST" >&2; exit 1; }
mkdir -p "$CM14" "$WORKSPACE_DIR/bin"

command -v git-lfs >/dev/null 2>&1 || {
  echo "ERROR: CM14.1's WebView prebuilt requires git-lfs." >&2
  echo "Install it manually: sudo apt-get install git-lfs" >&2
  exit 1
}

hydrate_webview_lfs() {
  [[ -d "$WEBVIEW_DIR" ]] || {
    echo "ERROR: CM14.1 WebView ARM prebuilt is missing" >&2
    return 1
  }
  git -C "$WEBVIEW_DIR" lfs pull --include=webview.apk github
  printf '%s  %s\n' "$WEBVIEW_APK_SHA256" "$WEBVIEW_APK" | sha256sum -c -
  [[ "$(stat -c '%s' "$WEBVIEW_APK")" == "$WEBVIEW_APK_SIZE" ]] || {
    echo "ERROR: unexpected WebView APK size" >&2
    return 1
  }
  unzip -tqq "$WEBVIEW_APK"
}

if [[ -z "$REPO_BIN" ]]; then
  if command -v repo >/dev/null 2>&1; then
    REPO_BIN=repo
  else
    REPO_BIN="$WORKSPACE_DIR/bin/repo"
    if [[ ! -x "$REPO_BIN" ]]; then
      curl -L --fail -o "$REPO_BIN" https://storage.googleapis.com/git-repo-downloads/repo
      chmod +x "$REPO_BIN"
    fi
  fi
fi

cd "$CM14"
INIT_ARGS=(-u https://github.com/LineageOS/android.git -b cm-14.1 --depth "${CM14_DEPTH:-1}")
if [[ -n "${CM14_REFERENCE:-}" ]]; then
  INIT_ARGS+=(--reference "$CM14_REFERENCE")
fi
"$REPO_BIN" init "${INIT_ARGS[@]}"

if [[ -f "$LOCK" ]]; then
  cp "$LOCK" .repo/manifests/lock.xml
  "$REPO_BIN" init -m lock.xml
else
  mkdir -p .repo/local_manifests
  cp "$LOCAL_MANIFEST" .repo/local_manifests/biscuit.xml
fi

for attempt in 1 2 3; do
  if "$REPO_BIN" sync -c --no-tags --fail-fast -j"${SYNC_JOBS:-4}"; then
    if [[ ! -f "$LOCK" ]]; then
      "$REPO_BIN" manifest -r -o "$LOCK"
      echo "Wrote resolved lock manifest: $LOCK"
    fi
    hydrate_webview_lfs
    echo "Hydrated CM14.1 WebView ARM APK."
    exit 0
  fi
  echo "repo sync failed (attempt $attempt/3)" >&2
  sleep $((attempt * 10))
done
exit 1
