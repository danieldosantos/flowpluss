const fs = require('fs');
const bcrypt = require('bcryptjs');

const template = fs.readFileSync('/usr/src/node-red/settings.template.js', 'utf8');
const adminUser = process.env.NODE_RED_ADMIN_USER || 'admin';
const adminPassword = process.env.NODE_RED_ADMIN_PASSWORD || 'TroqueEstaSenhaAgora!123';
const credentialSecret = process.env.NODE_RED_CREDENTIAL_SECRET || 'change-me';
const adminHash = bcrypt.hashSync(adminPassword, 10);

for (const placeholder of ['__ADMIN_USER__', '__ADMIN_HASH__', '__CREDENTIAL_SECRET__']) {
  if (!template.includes(placeholder)) {
    throw new Error(`Missing placeholder ${placeholder} in settings.template.js`);
  }
}

const rendered = template
  .replace(/__ADMIN_USER__/g, JSON.stringify(adminUser))
  .replace(/__ADMIN_HASH__/g, JSON.stringify(adminHash))
  .replace(/__CREDENTIAL_SECRET__/g, JSON.stringify(credentialSecret));

fs.writeFileSync('/data/settings.js', rendered, 'utf8');
console.log('settings.js generated');
