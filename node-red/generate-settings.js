const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');

const template = fs.readFileSync('/usr/src/node-red/settings.template.js', 'utf8');
const adminUser = String(process.env.NODE_RED_ADMIN_USER || 'admin').trim();
const adminPassword = String(process.env.NODE_RED_ADMIN_PASSWORD || '');
const credentialSecret = String(process.env.NODE_RED_CREDENTIAL_SECRET || '');
const cookieSecret = String(process.env.NODE_RED_COOKIE_SECRET || '');
const webhookHmacSecret = process.env.WEBHOOK_HMAC_SECRET || '';
const webhookHmacSecretPrevious = process.env.WEBHOOK_HMAC_SECRET_PREVIOUS || '';
const webhookSignatureMaxAgeMs = Number(process.env.WEBHOOK_SIGNATURE_MAX_AGE_MS || '300000');
const allowedOrigins = (process.env.NODE_RED_ALLOWED_ORIGINS || 'http://127.0.0.1:1880,http://localhost:1880')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);
const loginRateLimitWindowMs = Number(process.env.NODE_RED_LOGIN_RATE_LIMIT_WINDOW_MS || '900000');
const loginRateLimitMaxAttempts = Number(process.env.NODE_RED_LOGIN_RATE_LIMIT_MAX_ATTEMPTS || '5');
const loginRateLimitBlockMs = Number(process.env.NODE_RED_LOGIN_RATE_LIMIT_BLOCK_MS || '1800000');
const adminPasswordMinLength = Number(process.env.NODE_RED_ADMIN_PASSWORD_MIN_LENGTH || '12');
const adminPasswordRotationDays = Number(process.env.NODE_RED_ADMIN_PASSWORD_ROTATION_DAYS || '90');
const metadataDir = process.env.NODE_RED_SECURITY_METADATA_DIR || '/data/security';
const metadataFile = process.env.NODE_RED_SECURITY_METADATA_FILE || 'node-red-admin-auth.json';
const metadataPath = path.join(metadataDir, metadataFile);

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
  '__LOGIN_RATE_LIMIT_BLOCK_MS__'
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
  .replace(/__LOGIN_RATE_LIMIT_BLOCK_MS__/g, String(loginRateLimitBlockMs));

fs.writeFileSync('/data/settings.js', rendered, 'utf8');
fs.mkdirSync(metadataDir, { recursive: true });
fs.writeFileSync(metadataPath, JSON.stringify({
  generatedAt: new Date().toISOString(),
  adminUser,
  adminPasswordConfiguredFromEnv: true,
  adminPasswordMinLength,
  adminPasswordRotationDays,
  adminPasswordFingerprint: passwordFingerprint,
  credentialSecretFingerprint: derivePasswordFingerprint(credentialSecret, cookieSecret),
  notes: [
    'Compare adminPasswordFingerprint with the running .env value to confirm which password is active.',
    'Rotate the admin password and the credential/cookie secrets together when an exposure is suspected.'
  ]
}, null, 2) + '\n', 'utf8');
console.log(`settings.js generated; admin password fingerprint=${passwordFingerprint}; metadata=${metadataPath}`);
