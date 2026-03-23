const crypto = require('crypto');

const webhookHmacSecrets = [__WEBHOOK_HMAC_SECRET__, __WEBHOOK_HMAC_SECRET_PREVIOUS__].filter(Boolean);
const webhookSignatureMaxAgeMs = __WEBHOOK_SIGNATURE_MAX_AGE_MS__;
const allowedNodeOrigins = __NODE_RED_ALLOWED_ORIGINS__;

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

    httpNodeCors: {
        origin: allowedNodeOrigins,
        methods: "POST"
    },

    httpNodeMiddleware: function(req, res, next) {
        if (req.method === 'POST' && req.path === '/evolution/webhook') {
            if (!hasValidWebhookSignature(req)) {
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

    contextStorage: {
        default: "memory",
        memory: {
            module: "memory"
        }
    },

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    functionTimeout: 10,

    editorTheme: {
        projects: {
            enabled: false
        }
    }
};
