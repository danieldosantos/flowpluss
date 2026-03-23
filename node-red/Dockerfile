FROM nodered/node-red:3.1.9

USER root
RUN cd /data && npm install --unsafe-perm --no-update-notifier --no-fund node-red-contrib-context-redis bcryptjs
COPY settings.template.js /usr/src/node-red/settings.template.js
COPY generate-settings.js /usr/src/node-red/generate-settings.js
COPY entrypoint.sh /usr/src/node-red/entrypoint.sh
RUN chmod +x /usr/src/node-red/entrypoint.sh
USER node-red

ENTRYPOINT ["/usr/src/node-red/entrypoint.sh"]
