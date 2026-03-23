const fs = require('fs');
const bcrypt = require('bcryptjs');

const template = fs.readFileSync('/usr/src/node-red/settings.template.js', 'utf8');
const adminUser = process.env.NODE_RED_ADMIN_USER || 'admin';
const adminPassword = process.env.NODE_RED_ADMIN_PASSWORD || 'TroqueEstaSenhaAgora!123';
const credentialSecret = process.env.NODE_RED_CREDENTIAL_SECRET || 'change-me';
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
const adminHash = bcrypt.hashSync(adminPassword, 10);

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
console.log('settings.js generated');
