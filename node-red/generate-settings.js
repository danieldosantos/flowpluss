const fs = require('fs');
const bcrypt = require('bcryptjs');

const template = fs.readFileSync('/usr/src/node-red/settings.template.js', 'utf8');
const adminUser = process.env.NODE_RED_ADMIN_USER || 'admin';
const adminPassword = process.env.NODE_RED_ADMIN_PASSWORD || 'TroqueEstaSenhaAgora!123';
const credentialSecret = process.env.NODE_RED_CREDENTIAL_SECRET || 'change-me';
const cookieSecret = process.env.NODE_RED_COOKIE_SECRET || 'change-me-cookie';
const adminHash = bcrypt.hashSync(adminPassword, 10);

const rendered = template
  .replace(/__ADMIN_USER__/g, adminUser)
  .replace(/__ADMIN_HASH__/g, adminHash)
  .replace(/__CREDENTIAL_SECRET__/g, credentialSecret)
  .replace(/__COOKIE_SECRET__/g, cookieSecret);

fs.writeFileSync('/data/settings.js', rendered, 'utf8');
console.log('settings.js generated');
