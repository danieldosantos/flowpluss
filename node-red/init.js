const fs = require('fs');
const bcrypt = require('bcryptjs');

const adminUser = process.env.NODE_RED_ADMIN_USER || 'admin';
const adminPassword = process.env.NODE_RED_ADMIN_PASSWORD || '';
const credentialSecret = process.env.NODE_RED_CREDENTIAL_SECRET || '';
const contextStorageMode = (process.env.NODE_RED_CONTEXT_STORAGE || 'memory').toLowerCase();

if (!adminPassword || !credentialSecret) {
  console.error('ERROR: NODE_RED_ADMIN_PASSWORD and NODE_RED_CREDENTIAL_SECRET are required');
  process.exit(1);
}

const adminHash = bcrypt.hashSync(adminPassword, 10);
const contextStorage = {
  default: contextStorageMode,
  memory: { module: 'memory' }
};

const settings = {
  uiPort: 1880,
  credentialSecret,
  adminAuth: {
    type: 'credentials',
    users: [{
      username: adminUser,
      password: adminHash,
      permissions: '*'
    }]
  },
  httpAdminCookieOptions: {
    httpOnly: true,
    sameSite: 'strict'
  },
  contextStorage,
  functionTimeout: 10,
  editorTheme: {
    projects: { enabled: false }
  }
};

fs.mkdirSync('/data/security', { recursive: true });
fs.writeFileSync('/data/settings.js', 'module.exports = ' + JSON.stringify(settings, null, 2), 'utf8');
console.log('Settings generated');
