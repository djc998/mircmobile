#!/bin/bash
# Lists the reports people sent from the app (messages and photos), newest
# first, with the last 24 hours marked NEW. The app's terms promise review
# within 24 hours, so run this at least once a day.
#
#   ./check-reports.sh          readable list
#   ./check-reports.sh --json   the raw JSON
#
# Uses $ADMIN_TOKEN if it's set, otherwise asks for it (nothing you type
# is shown). Set $PICTURE_HOST to check a different deployment.
set -euo pipefail
cd "$(dirname "$0")"
export PATH=/opt/homebrew/bin:$PATH

HOST="${PICTURE_HOST:-https://irc-pictures.irc-pictures.workers.dev}"
TOKEN="${ADMIN_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  read -r -s -p "Admin token (from your password manager), then Return: " TOKEN
  echo
fi
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]')
if [ -z "$TOKEN" ]; then
  echo "No token given." >&2
  exit 1
fi

# The token goes in a header read from stdin, so it never shows up in the
# process list.
BODY=$(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" |
  curl -s --fail-with-body --config - "$HOST/admin/reports") || {
  echo "Couldn't get the reports: ${BODY:-no answer from $HOST}" >&2
  if printf '%s' "${BODY:-}" | grep -q 'Not allowed'; then
    echo "That token doesn't match the server's ADMIN_TOKEN." >&2
  fi
  exit 1
}

if [ "${1:-}" = "--json" ]; then
  printf '%s\n' "$BODY"
else
  printf '%s' "$BODY" | node tools/format-reports.js
fi
