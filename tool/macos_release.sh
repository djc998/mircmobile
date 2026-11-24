#!/bin/bash
# Signs IRCage.app with a Developer ID, has Apple notarize it, staples the
# result and zips it as IRCage-macOS.zip, so Gatekeeper opens it without a
# warning. Used by .github/workflows/release.yml; works on a Mac too.
#
#   tool/macos_release.sh path/to/IRCage.app
#
# Needs, in the environment:
#   SIGN_IDENTITY    e.g. "Developer ID Application: Your Name (TEAMID)"
#                    (in the login keychain, or the one in KEYCHAIN)
#   KEYCHAIN         optional: keychain holding the identity
#   ASC_KEY_PATH     App Store Connect API key (.p8) file
#   ASC_KEY_ID       its Key ID
#   ASC_ISSUER_ID    its Issuer ID
#   NOTARIZE=0       optional: only sign (a quick local check)
set -euo pipefail

APP="${1:?usage: tool/macos_release.sh path/to/IRCage.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"
OUT="${OUT:-$PWD/IRCage-macOS.zip}"
: "${SIGN_IDENTITY:?set SIGN_IDENTITY}"
NOTARIZE="${NOTARIZE:-1}"
if [ "$NOTARIZE" != "0" ]; then
  : "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
  : "${ASC_KEY_ID:?set ASC_KEY_ID}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
fi

sign() {
  codesign --force --options runtime --timestamp \
    ${KEYCHAIN:+--keychain "$KEYCHAIN"} \
    --sign "$SIGN_IDENTITY" "$@"
}

echo "▸ Signing nested code"
# Innermost first: libraries, then frameworks, then the app itself.
while IFS= read -r -d '' item; do
  sign "$item"
done < <(find "$APP/Contents" \( -name '*.dylib' -o -name '*.so' \) -type f -print0)
while IFS= read -r -d '' item; do
  sign "$item"
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0)

echo "▸ Signing IRCage.app"
sign --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$NOTARIZE" = "0" ]; then
  echo "▸ Signed (not notarized: NOTARIZE=0)"
  exit 0
fi

echo "▸ Notarizing (this usually takes a few minutes)"
SUBMIT="$(mktemp -d)/IRCage-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT"
RESULT="$(xcrun notarytool submit "$SUBMIT" \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait --timeout 30m --output-format json)"
echo "$RESULT"
STATUS="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$RESULT")"
if [ "$STATUS" != "Accepted" ]; then
  ID="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"$RESULT")"
  echo "::error::Notarization $STATUS"
  [ -n "$ID" ] && xcrun notarytool log "$ID" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
  exit 1
fi

echo "▸ Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
# What Gatekeeper will say on someone else's Mac.
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
echo "▸ Done: $OUT"
