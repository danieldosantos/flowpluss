#!/bin/sh
set -e

node /usr/src/node-red/init.js

FLOW_FILE="/data/flows.json"
DEFAULT_FLOW="/usr/src/node-red/flows_secure.json"

if [ ! -s "$FLOW_FILE" ] || grep -Eq '^[[:space:]]*\[[[:space:]]*\][[:space:]]*$' "$FLOW_FILE"; then
  cp "$DEFAULT_FLOW" "$FLOW_FILE"
  echo "Bootstrapped /data/flows.json from hardened default flow"
fi

exec npm start -- --userDir /data --settings /data/settings.js
