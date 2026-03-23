const http = require('http');
const crypto = require('crypto');

const port = Number(process.env.PORT || '3000');
const forwardHost = process.env.FORWARD_HOST || 'node-red';
const forwardPort = Number(process.env.FORWARD_PORT || '1880');
const forwardPath = process.env.FORWARD_PATH || '/evolution/webhook';
const signingSecret = process.env.WEBHOOK_HMAC_SECRET || '';
const acceptedTokens = [
  process.env.WEBHOOK_SECRET || '',
  process.env.WEBHOOK_SECRET_PREVIOUS || ''
].filter(Boolean);

if (!signingSecret) {
  throw new Error('WEBHOOK_HMAC_SECRET is required');
}

if (acceptedTokens.length === 0) {
  throw new Error('WEBHOOK_SECRET is required');
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

function isAcceptedToken(token) {
  return acceptedTokens.some((candidate) => safeEqual(candidate, token));
}

function respondJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/healthz') {
    respondJson(res, 200, { ok: true });
    return;
  }

  if (req.method !== 'POST' || url.pathname !== '/evolution/webhook') {
    respondJson(res, 404, { ok: false, error: 'not_found' });
    return;
  }

  const token = url.searchParams.get('token') || '';
  if (!isAcceptedToken(token)) {
    respondJson(res, 401, { ok: false, error: 'invalid_token' });
    return;
  }

  let rawBody = '';
  req.setEncoding('utf8');
  req.on('data', (chunk) => {
    rawBody += chunk;
    if (rawBody.length > 1024 * 1024) {
      req.destroy(new Error('payload_too_large'));
    }
  });

  req.on('error', () => {
    if (!res.headersSent) {
      respondJson(res, 413, { ok: false, error: 'payload_error' });
    }
  });

  req.on('end', () => {
    let parsedBody = {};
    try {
      parsedBody = rawBody ? JSON.parse(rawBody) : {};
    } catch (error) {
      respondJson(res, 400, { ok: false, error: 'invalid_json' });
      return;
    }

    const timestamp = String(Date.now());
    const bodyDigest = digestPayload(parsedBody);
    const signature = crypto
      .createHmac('sha256', signingSecret)
      .update(`${timestamp}.${bodyDigest}`, 'utf8')
      .digest('hex');

    const proxyReq = http.request(
      {
        host: forwardHost,
        port: forwardPort,
        path: forwardPath,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(rawBody),
          'x-flowpluss-timestamp': timestamp,
          'x-flowpluss-body-sha256': bodyDigest,
          'x-flowpluss-signature': signature
        }
      },
      (proxyRes) => {
        const responseChunks = [];
        proxyRes.on('data', (chunk) => responseChunks.push(chunk));
        proxyRes.on('end', () => {
          const responseBody = Buffer.concat(responseChunks);
          res.writeHead(proxyRes.statusCode || 502, {
            'Content-Type': proxyRes.headers['content-type'] || 'application/json'
          });
          res.end(responseBody);
        });
      }
    );

    proxyReq.on('error', () => {
      respondJson(res, 502, { ok: false, error: 'upstream_unavailable' });
    });

    proxyReq.write(rawBody);
    proxyReq.end();
  });
});

server.listen(port, '0.0.0.0', () => {
  console.log(`webhook gateway listening on ${port}`);
});
