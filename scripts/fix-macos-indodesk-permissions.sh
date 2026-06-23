#!/usr/bin/env bash
# Fix macOS privacy permission issues for ad-hoc IndoDesk builds.
# Run after installing IndoDesk User from DMG:
#   bash scripts/fix-macos-indodesk-permissions.sh
set -euo pipefail

APP_NAME="${INODESK_APP_NAME:-IndoDesk User}"
APP="${APP_OVERRIDE:-/Applications/${APP_NAME}.app}"
BUNDLE_ID="${INODESK_BUNDLE_ID:-com.carriez.rustdesk}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 1
fi

echo "==> Quit ${APP_NAME} if running..."
if [[ -z "${APP_OVERRIDE:-}" ]]; then
  osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
  sleep 1
  pkill -x "${APP_NAME}" 2>/dev/null || true
fi

echo "==> Remove quarantine (downloaded DMG gatekeeper flag)..."
xattr -cr "$APP"

echo "==> Re-sign nested binaries with bundle id ${BUNDLE_ID}..."
sign() {
  codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$1"
}

while IFS= read -r -d '' bin; do
  sign "$bin"
done < <(find "$APP/Contents" \( -name "*.dylib" -o -perm -111 \) -type f -print0)

sign "$APP/Contents/MacOS/${APP_NAME}"
sign "$APP/Contents/MacOS/service" 2>/dev/null || true
sign "$APP"

echo "==> Reset privacy TCC entries..."
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "Done. Grant each permission when IndoDesk shows the green card:"
echo "  1. Screen Recording -> Configure -> Allow -> Quit (Cmd+Q) -> reopen"
echo "  2. Accessibility    -> Configure -> Allow -> Quit (Cmd+Q) -> reopen"
echo "  3. Input Monitoring -> Configure -> Allow -> Quit (Cmd+Q) -> reopen"
