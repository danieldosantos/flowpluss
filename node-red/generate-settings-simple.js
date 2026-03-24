const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');

try {
  const adminUser = String(process.env.NODE_RED_ADMIN_USER || 'admin').trim();
  const adminPassword = String(process.env.NODE_RED_ADMIN_PASSWORD || '');
  const credentialSecret = String(process.env.NODE_RED_CREDENTIAL_SECRET || '');
  const contextStorageMode = String(process.env.NODE_RED_CONTEXT_STORAGE || 'memory').trim().toLowerCase();
  const redisHost = String(process.env.REDIS_HOST || 'redis').trim();
  const redisPort = Number(process.env.REDIS_PORT || '6379');
  const redisDb = Number(process.env.REDIS_DB || '0');
  const redisPassword = String(process.env.REDIS_PASSWORD || '');

  // Build context storage config
  const contextStorageConfig = {
    default: contextStorageMode,
    memory: {
      module: 'memory'
    }
  };

  // Generate admin password hash
  const adminHash = bcrypt.hashSync(adminPassword, 10);

  // Read and process template
  let template = fs.readFileSync('/usr/src/node-red/settings-simple.js', 'utf8');
  
  template = template
    .replace('__ADMIN_USER__', JSON.stringify(adminUser))
    .replace('__ADMIN_HASH__', JSON.stringify(adminHash))
    .replace('__CREDENTIAL_SECRET__', JSON.stringify(credentialSecret))
    .replace('__CONTEXT_STORAGE_CONFIG__', JSON.stringify(contextStorageConfig, null, 2));

  // Write settings.js
  fs.writeFileSync('/data/settings.js', template, 'utf8');

  // Write metadata
  const metadataDir = '/data/security';
  fs.mkdirSync(metadataDir, { recursive: true });
  fs.writeFileSync(path.join(metadataDir, 'node-red-admin-auth.json'), JSON.stringify({
    generatedAt: new Date().toISOString(),
    adminUser
  }, null, 2), 'utf8');

  console.log('settings.js generated successfully');
} catch (err) {
  console.error('ERROR generating settings.js:', err.message);
  process.exit(1);
}
