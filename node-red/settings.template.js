const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const webhookHmacSecrets = [__WEBHOOK_HMAC_SECRET__, __WEBHOOK_HMAC_SECRET_PREVIOUS__].filter(Boolean);
const webhookSignatureMaxAgeMs = __WEBHOOK_SIGNATURE_MAX_AGE_MS__;
const allowedNodeOrigins = __NODE_RED_ALLOWED_ORIGINS__;
const loginRateLimitWindowMs = __LOGIN_RATE_LIMIT_WINDOW_MS__;
const loginRateLimitMaxAttempts = __LOGIN_RATE_LIMIT_MAX_ATTEMPTS__;
const loginRateLimitBlockMs = __LOGIN_RATE_LIMIT_BLOCK_MS__;
const loginRateLimitStore = new Map();
const auditLogDir = process.env.NODE_RED_AUDIT_LOG_DIR || '/data/logs';
const auditLogFile = process.env.NODE_RED_AUDIT_LOG_FILE || 'node-red-audit.jsonl';
const auditLogPath = path.join(auditLogDir, auditLogFile);

function ensureAuditStream() {
    fs.mkdirSync(auditLogDir, { recursive: true });
    return fs.createWriteStream(auditLogPath, { flags: 'a', encoding: 'utf8' });
}

const auditStream = ensureAuditStream();

function writeAuditEvent(event) {
    auditStream.write(JSON.stringify({
        recordedAt: new Date().toISOString(),
        ...event
    }) + '\n');
}

function logSecurityEvent(event, details) {
    writeAuditEvent({
        source: 'flowpluss',
        event,
        details: details || {}
    });
}

function canonicalize(value) {
    if (value === null || typeof value !== 'object') {
        return JSON.stringify(value);
    }

    if (Array.isArray(value)) {
        return '[' + value.map(canonicalize).join(',') + ']';
    }

    const keys = Object.keys(value).sort();
    return '{' + keys.map((key) => JSON.stringify(key) + ':' + canonicalize(value[key])).join(',') + '}';
}

function digestPayload(payload) {
    return crypto.createHash('sha256').update(canonicalize(payload), 'utf8').digest('hex');
}

function safeEqual(left, right) {
    const leftBuffer = Buffer.from(String(left || ''), 'utf8');
    const rightBuffer = Buffer.from(String(right || ''), 'utf8');
    if (leftBuffer.length !== rightBuffer.length) {
        return false;
    }

    return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function hasValidWebhookSignature(req) {
    const timestamp = String(req.headers['x-flowpluss-timestamp'] || '');
    const signature = String(req.headers['x-flowpluss-signature'] || '');
    const bodyDigest = String(req.headers['x-flowpluss-body-sha256'] || '');

    if (!timestamp || !signature || !bodyDigest || webhookHmacSecrets.length === 0) {
        return false;
    }

    const issuedAt = Number(timestamp);
    if (!Number.isFinite(issuedAt)) {
        return false;
    }

    if (Math.abs(Date.now() - issuedAt) > webhookSignatureMaxAgeMs) {
        return false;
    }

    const payloadDigest = digestPayload(req.body || {});
    if (!safeEqual(payloadDigest, bodyDigest)) {
        return false;
    }

    const material = `${timestamp}.${bodyDigest}`;
    return webhookHmacSecrets.some((secret) => {
        const expected = crypto.createHmac('sha256', secret).update(material, 'utf8').digest('hex');
        return safeEqual(expected, signature);
    });
}


function getClientIp(req) {
    const forwardedFor = req.headers['x-forwarded-for'];
    if (typeof forwardedFor === 'string' && forwardedFor.trim()) {
        return forwardedFor.split(',')[0].trim();
    }

    return String(req.ip || req.connection?.remoteAddress || 'unknown');
}

function cleanupLoginRateLimitStore(now) {
    for (const [key, entry] of loginRateLimitStore.entries()) {
        const idleForMs = now - Math.max(entry.lastAttemptAt || 0, entry.blockedUntil || 0);
        if (idleForMs > Math.max(loginRateLimitWindowMs, loginRateLimitBlockMs)) {
            loginRateLimitStore.delete(key);
        }
    }
}

function loginRateLimitMiddleware(req, res, next) {
    if (req.method !== 'POST' || req.path !== '/auth/token') {
        next();
        return;
    }

    const now = Date.now();
    cleanupLoginRateLimitStore(now);

    const username = String(req.body?.username || '').trim().toLowerCase() || 'unknown';
    const clientIp = getClientIp(req);
    const rateKey = `${clientIp}:${username}`;
    const current = loginRateLimitStore.get(rateKey);

    if (current && current.blockedUntil > now) {
        const retryAfterSeconds = Math.max(1, Math.ceil((current.blockedUntil - now) / 1000));
        logSecurityEvent('admin.login.blocked', {
            username,
            clientIp,
            retryAfterSeconds,
            blockedUntil: new Date(current.blockedUntil).toISOString()
        });
        res.setHeader('Retry-After', String(retryAfterSeconds));
        res.status(429).json({ ok: false, error: 'too_many_login_attempts', retry_after_seconds: retryAfterSeconds });
        return;
    }

    res.on('finish', () => {
        const finishedAt = Date.now();
        cleanupLoginRateLimitStore(finishedAt);

        const baseEvent = {
            username,
            clientIp,
            statusCode: res.statusCode,
            method: req.method,
            path: req.path
        };

        if (res.statusCode < 400) {
            loginRateLimitStore.delete(rateKey);
            logSecurityEvent('admin.login.success', baseEvent);
            return;
        }

        const stored = loginRateLimitStore.get(rateKey);
        const entry = !stored || (finishedAt - stored.windowStartedAt) >= loginRateLimitWindowMs
            ? { count: 0, windowStartedAt: finishedAt, blockedUntil: 0 }
            : stored;

        entry.count += 1;
        entry.lastAttemptAt = finishedAt;
        if (entry.count >= loginRateLimitMaxAttempts) {
            entry.blockedUntil = finishedAt + loginRateLimitBlockMs;
        }

        loginRateLimitStore.set(rateKey, entry);
        logSecurityEvent('admin.login.failure', {
            ...baseEvent,
            attemptCount: entry.count,
            windowStartedAt: new Date(entry.windowStartedAt).toISOString(),
            blockedUntil: entry.blockedUntil ? new Date(entry.blockedUntil).toISOString() : null
        });
    });

    next();
}

module.exports = {
    flowFile: 'flows.json',

    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",

    httpAdminRoot: '/',
    httpNodeRoot: '/',

    functionGlobalContext: {},

    adminAuth: {
        type: "credentials",
        users: [{
            username: __ADMIN_USER__,
            password: __ADMIN_HASH__,
            permissions: "*"
        }]
    },

    credentialSecret: __CREDENTIAL_SECRET__,

    httpAdminMiddleware: [loginRateLimitMiddleware],

    httpNodeCors: {
        origin: allowedNodeOrigins,
        methods: "POST"
    },

    httpNodeMiddleware: function(req, res, next) {
        if (req.method === 'POST' && req.path === '/evolution/webhook') {
            if (!hasValidWebhookSignature(req)) {
                logSecurityEvent('webhook.signature.rejected', {
                    clientIp: getClientIp(req),
                    path: req.path,
                    method: req.method,
                    bodyDigest: String(req.headers['x-flowpluss-body-sha256'] || ''),
                    timestamp: String(req.headers['x-flowpluss-timestamp'] || '')
                });
                res.status(401).json({ ok: false, error: 'invalid_webhook_signature' });
                return;
            }
        }

        next();
    },

    httpAdminCookieOptions: {
        httpOnly: true,
        sameSite: 'strict'
    },

    contextStorage: __CONTEXT_STORAGE_CONFIG__,

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: true
        },
        auditTrail: {
            level: "info",
            metrics: false,
            audit: true,
            handler: function(msg) {
                writeAuditEvent({
                    source: 'node-red',
                    ...msg
                });
            }
        }
    },

    functionTimeout: 10,

    editorTheme: {
        projects: {
            enabled: false
        }
    }
};
