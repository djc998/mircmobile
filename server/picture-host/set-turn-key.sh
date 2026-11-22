#!/bin/bash
# Asks for a Cloudflare TURN key (Turn Token ID + API Token), checks it with
# Cloudflare, and only then saves it as the Worker's TURN_KEY_ID and
# TURN_KEY_API_TOKEN secrets. Nothing you type is shown on screen.
set -euo pipefail
cd "$(dirname "$0")"
export PATH=/opt/homebrew/bin:$PATH

read -r -s -p "Paste the Turn Token ID (32 characters), then Return: " KEY_ID; echo
read -r -s -p "Paste the API Token (64 characters), then Return: " API_TOKEN; echo
KEY_ID=$(printf '%s' "$KEY_ID" | tr -d '[:space:]')
API_TOKEN=$(printf '%s' "$API_TOKEN" | tr -d '[:space:]')
echo "Got an ID of ${#KEY_ID} characters and a token of ${#API_TOKEN} characters."

echo "Checking with Cloudflare…"
status=$(curl -s -o /tmp/turn-check.$$ -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
  -d '{"ttl":600}' \
  "https://rtc.live.cloudflare.com/v1/turn/keys/$KEY_ID/credentials/generate-ice-servers")
answer=$(cat /tmp/turn-check.$$); rm -f /tmp/turn-check.$$
if [ "$status" != "200" ] && [ "$status" != "201" ]; then
  echo "✘ Cloudflare said no ($status): $answer"
  echo "  Make sure both values come from Realtime → TURN Server (not Serverless SFU)."
  echo "  Nothing was saved."
  exit 1
fi
echo "✔ The key works. Saving it to the server…"
printf '%s' "$KEY_ID" | npx wrangler secret put TURN_KEY_ID >/dev/null
printf '%s' "$API_TOKEN" | npx wrangler secret put TURN_KEY_API_TOKEN >/dev/null
echo "✔ Saved. Tell Claude \"done\"."
