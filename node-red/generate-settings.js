const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');

const template = fs.readFileSync('/usr/src/node-red/settings-simple.js', 'utf8');
const adminUser = String(process.env.NODE_RED_ADMIN_USER || 'admin').trim();
const adminPassword = String(process.env.NODE_RED_ADMIN_PASSWORD || '');
const credentialSecret = String(process.env.NODE_RED_CREDENTIAL_SECRET || '');
const contextStorageMode = String(process.env.NODE_RED_CONTEXT_STORAGE || 'memory').trim().toLowerCase();
const redisHost = String(process.env.REDIS_HOST || 'redis').trim();
const redisPort = Number(process.env.REDIS_PORT || '6379');
const redisDb = Number(process.env.REDIS_DB || '0');
const redisPassword = String(process.env.REDIS_PASSWORD || '');

function isPlaceholderValue(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) {
    return true;
  }

  return [
    'change-me',
    'changeme',
    'admin',
    'password',
    '123456',
    'troque-por-uma-senha-unica-e-forte',
    'troqueestasenhaagora!123',
    'troque-por-um-segredo-de-credenciais',
    'troque-por-um-segredo-de-cookie'
  ].includes(normalized);
}

function assertSecret(name, value) {
  if (isPlaceholderValue(value)) {
    throw new Error(`${name} must be set to a unique non-placeholder secret`);
  }
}

function derivePasswordFingerprint(password, secret) {
  return crypto
    .createHmac('sha256', secret)
    .update(password, 'utf8')
    .digest('hex')
    .slice(0, 16);
}

for (const placeholder of [
  '__ADMIN_USER__',
  '__ADMIN_HASH__',
  '__CREDENTIAL_SECRET__',
  '__WEBHOOK_HMAC_SECRET__',
  '__WEBHOOK_HMAC_SECRET_PREVIOUS__',
  '__WEBHOOK_SIGNATURE_MAX_AGE_MS__',
  '__NODE_RED_ALLOWED_ORIGINS__',
  '__LOGIN_RATE_LIMIT_WINDOW_MS__',
  '__LOGIN_RATE_LIMIT_MAX_ATTEMPTS__',
  '__LOGIN_RATE_LIMIT_BLOCK_MS__',
  '__CONTEXT_STORAGE_CONFIG__'
]) {
  if (!template.includes(placeholder)) {
    throw new Error(`Missing placeholder ${placeholder} in settings.template.js`);
  }
}

if (!adminUser) {
  throw new Error('NODE_RED_ADMIN_USER is required');
}

if (!Number.isInteger(adminPasswordMinLength) || adminPasswordMinLength < 8) {
  throw new Error('NODE_RED_ADMIN_PASSWORD_MIN_LENGTH must be an integer >= 8');
}

if (!Number.isInteger(adminPasswordRotationDays) || adminPasswordRotationDays < 1) {
  throw new Error('NODE_RED_ADMIN_PASSWORD_ROTATION_DAYS must be an integer >= 1');
}

assertSecret('NODE_RED_ADMIN_PASSWORD', adminPassword);
assertSecret('NODE_RED_CREDENTIAL_SECRET', credentialSecret);
assertSecret('NODE_RED_COOKIE_SECRET', cookieSecret);

if (adminPassword.length < adminPasswordMinLength) {
  throw new Error(`NODE_RED_ADMIN_PASSWORD must contain at least ${adminPasswordMinLength} characters`);
}

if (adminPassword.toLowerCase().includes(adminUser.toLowerCase())) {
  throw new Error('NODE_RED_ADMIN_PASSWORD must not contain NODE_RED_ADMIN_USER');
}

if (!webhookHmacSecret) {
  throw new Error('WEBHOOK_HMAC_SECRET is required to protect the webhook');
}

if (!Number.isFinite(webhookSignatureMaxAgeMs) || webhookSignatureMaxAgeMs < 1000) {
  throw new Error('WEBHOOK_SIGNATURE_MAX_AGE_MS must be a number >= 1000');
}

if (!Number.isFinite(loginRateLimitWindowMs) || loginRateLimitWindowMs < 1000) {
  throw new Error('NODE_RED_LOGIN_RATE_LIMIT_WINDOW_MS must be a number >= 1000');
}

if (!Number.isInteger(loginRateLimitMaxAttempts) || loginRateLimitMaxAttempts < 1) {
  throw new Error('NODE_RED_LOGIN_RATE_LIMIT_MAX_ATTEMPTS must be an integer >= 1');
}

if (!Number.isFinite(loginRateLimitBlockMs) || loginRateLimitBlockMs < 1000) {
  throw new Error('NODE_RED_LOGIN_RATE_LIMIT_BLOCK_MS must be a number >= 1000');
}

if (!['redis', 'memory'].includes(contextStorageMode)) {
  throw new Error('NODE_RED_CONTEXT_STORAGE must be either "redis" or "memory"');
}

if (!Number.isInteger(redisPort) || redisPort < 1 || redisPort > 65535) {
  throw new Error('REDIS_PORT must be an integer between 1 and 65535');
}

if (!Number.isInteger(redisDb) || redisDb < 0 || redisDb > 15) {
  throw new Error('REDIS_DB must be an integer between 0 and 15');
}

if (contextStorageMode === 'redis' && !redisHost) {
  throw new Error('REDIS_HOST is required when NODE_RED_CONTEXT_STORAGE=redis');
}

if (contextStorageMode === 'redis' && !redisKeyPrefix) {
  throw new Error('NODE_RED_REDIS_PREFIX must not be empty when NODE_RED_CONTEXT_STORAGE=redis');
}

const contextStorageConfig = contextStorageMode === 'redis'
  ? {
      default: 'redis',
      redis: {
        module: 'node-red-contrib-context-redis',
        config: {
          host: redisHost,
          port: redisPort,
          db: redisDb,
          prefix: redisKeyPrefix,
          password: redisPassword || undefined
        }
      },
      memory: {
        module: 'memory'
      }
    }
  : {
      default: 'memory',
      memory: {
        module: 'memory'
      }
    };

const adminHash = bcrypt.hashSync(adminPassword, 10);
const passwordFingerprint = derivePasswordFingerprint(adminPassword, credentialSecret);

const rendered = template
  .replace(/__ADMIN_USER__/g, JSON.stringify(adminUser))
  .replace(/__ADMIN_HASH__/g, JSON.stringify(adminHash))
  .replace(/__CREDENTIAL_SECRET__/g, JSON.stringify(credentialSecret))
  .replace(/__WEBHOOK_HMAC_SECRET__/g, JSON.stringify(webhookHmacSecret))
  .replace(/__WEBHOOK_HMAC_SECRET_PREVIOUS__/g, JSON.stringify(webhookHmacSecretPrevious))
  .replace(/__WEBHOOK_SIGNATURE_MAX_AGE_MS__/g, String(webhookSignatureMaxAgeMs))
  .replace(/__NODE_RED_ALLOWED_ORIGINS__/g, JSON.stringify(allowedOrigins))
  .replace(/__LOGIN_RATE_LIMIT_WINDOW_MS__/g, String(loginRateLimitWindowMs))
  .replace(/__LOGIN_RATE_LIMIT_MAX_ATTEMPTS__/g, String(loginRateLimitMaxAttempts))
  .replace(/__LOGIN_RATE_LIMIT_BLOCK_MS__/g, String(loginRateLimitBlockMs))
  .replace(/__CONTEXT_STORAGE_CONFIG__/g, JSON.stringify(contextStorageConfig, null, 4));

fs.writeFileSync('/data/settings.js', rendered, 'utf8');
fs.mkdirSync(metadataDir, { recursive: true });
fs.writeFileSync(metadataPath, JSON.stringify({
  generatedAt: new Date().toISOString(),
  adminUser,
  adminPasswordConfiguredFromEnv: true,
  adminPasswordMinLength,
  adminPasswordRotationDays,
  nodeRedContextStorage: contextStorageMode,
  redisContextStoreEnabled: contextStorageMode === 'redis',
  redisContextHost: contextStorageMode === 'redis' ? redisHost : null,
  redisContextPort: contextStorageMode === 'redis' ? redisPort : null,
  redisContextDb: contextStorageMode === 'redis' ? redisDb : null,
  redisContextPrefix: contextStorageMode === 'redis' ? redisKeyPrefix : null,
  adminPasswordFingerprint: passwordFingerprint,
  credentialSecretFingerprint: derivePasswordFingerprint(credentialSecret, cookieSecret),
  notes: [
    'Compare adminPasswordFingerprint with the running .env value to confirm which password is active.',
    'Rotate the admin password and the credential/cookie secrets together when an exposure is suspected.'
  ]
}, null, 2) + '\n', 'utf8');
console.log(`settings.js generated; admin password fingerprint=${passwordFingerprint}; metadata=${metadataPath}`);
