#!/bin/sh
set -e
node /usr/src/node-red/generate-settings.js
exec npm start -- --userDir /data --settings /data/settings.js
