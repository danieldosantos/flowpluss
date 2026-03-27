FROM nodered/node-red:3.1.9

USER root

# Install bcryptjs for password hashing
RUN cd /usr/src/node-red && npm install --unsafe-perm --no-update-notifier --no-fund bcryptjs

# Ship hardened defaults and startup scripts
COPY flows_secure.json /usr/src/node-red/flows_secure.json
COPY init.js /usr/src/node-red/init.js
COPY entrypoint.sh /usr/src/node-red/entrypoint.sh

# Normalize line endings in case the repo was checked out on Windows
RUN sed -i 's/\r$//' /usr/src/node-red/entrypoint.sh /usr/src/node-red/init.js \
    && chmod +x /usr/src/node-red/entrypoint.sh

USER node-red
ENTRYPOINT ["/usr/src/node-red/entrypoint.sh"]
