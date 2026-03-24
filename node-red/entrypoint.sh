#!/bin/sh
set -e
node /usr/src/node-red/generate-settings-simple.js
exec npm start -- --userDir /data --settings /data/settings.js
