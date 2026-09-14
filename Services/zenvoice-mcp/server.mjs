// MCP relay: OAuth 2.1 + device pull/push. Does not store transcripts.
// In-memory only. Do not log request or response bodies.
import http from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import assert from 'node:assert/strict';

const nonce = () => randomBytes(32).toString('base64url');
const digest = value => createHash('sha256').update(value).digest('base64url');
const equal = (a, b) => {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
};
const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };
const originOf = value => (value ?? '').replace(/\/+$/, '');
const connectPath = '/connect/mcp';
const connectUrl = origin => `${origin}${connectPath}`;
const pairingOf = () => {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = randomBytes(6);
  let out = '';
  for (const byte of bytes) out += alphabet[byte % alphabet.length];
  return out;
};

const devices = new Map();
const clients = new Map();
const codes = new Map();
const tokens = new Map();
const pulls = new Map();
const pending = new Map();

let windowStart = Date.now();
let requests = 0;
const waitMs = () => Number(process.env.MCP_WAIT_MS ?? 20_000);

const html = (title, body) =>
  '<!doctype html><html><head><meta charset="utf-8"><title>' +
  escape(title) +
  '</title></head><body>' +
  body +
  '</body></html>';
const escape = value => String(value).replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));

function json(response, status, value, extra = {}) {
  const headers = { 'content-type': 'application/json', 'cache-control': 'no-store', ...extra };
  response.writeHead(status, headers);
  response.end(JSON.stringify(value));
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', chunk => {
      size += chunk.length;
      if (size > 1_000_000) { reject(Object.assign(new Error('Payload too large'), { status: 413 })); request.destroy(); return; }
      chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks)));
    request.on('error', reject);
  });
}

async function parseBody(request) {
  const raw = await readBody(request);
  const type = request.headers['content-type'] || '';
  if (type.includes('application/x-www-form-urlencoded')) return Object.fromEntries(new URLSearchParams(raw.toString('utf8')));
  if (!raw.length) return {};
  return JSON.parse(raw.toString('utf8'));
}

function requireOrigin(url) {
  const origin = originOf(process.env.PUBLIC_ORIGIN) || `${url.protocol}//${url.host}`;
  const parsed = new URL(origin);
  const local = parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost';
  if (!local && parsed.protocol !== 'https:') fail(503, 'A public HTTPS origin is required');
  return origin;
}

function device(id) {
  const row = devices.get(id);
  if (!row) fail(404, 'Unknown Mac');
  return row;
}

function bearer(request) {
  const header = request.headers.authorization || '';
  const match = /^Bearer (.+)$/.exec(header);
  if (!match) return '';
  return match[1];
}

function authWWW(origin) {
  return `Bearer FAKESECRET_g3h4i5j6k7l8m9n0o1p2="${origin}/.well-known/oauth-protected-resource", scope="meetings.read"`;
}

function resolveDevice(url, input = {}) {
  const pairing = String(url.searchParams.get('pairing') || input.pairing || '').trim().toUpperCase();
  if (pairing) {
    for (const [id, row] of devices) if (row.pairing === pairing) return id;
    fail(400, 'Unknown pairing code');
  }
  const resource = url.searchParams.get('resource') || '';
  const fromResource = (resource.match(/\/d\/([^/]+)\/mcp/) || [])[1];
  if (fromResource && devices.has(fromResource)) return fromResource;
  const deviceParam = url.searchParams.get('device') || '';
  if (deviceParam && devices.has(deviceParam)) return deviceParam;
  const online = [...pulls.keys()];
  if (online.length === 1) return online[0];
  if (online.length === 0) fail(400, 'Open ZenVoice and turn on AI connectors.');
  fail(400, 'Enter the pairing code shown in ZenVoice.');
}

function deliverPull(deviceId, payload) {
  const waiter = pulls.get(deviceId);
  if (!waiter) return false;
  pulls.delete(deviceId);
  clearTimeout(waiter.timer);
  waiter.resolve(payload);
  return true;
}

async function proxyMcp(response, origin, deviceId, rpc) {
  device(deviceId);
  const responseBody = await new Promise((resolve, reject) => {
    const requestId = nonce();
    const timer = setTimeout(() => {
      pending.delete(requestId);
      reject(Object.assign(new Error('ZenVoice is not running on that Mac.'), { status: 503 }));
    }, waitMs());
    pending.set(requestId, { deviceId, resolve, timer, waiting: true, rpc });
    if (deliverPull(deviceId, { requestId, jsonrpc: rpc })) {
      pending.get(requestId).waiting = false;
    }
  });
  return json(response, 200, responseBody);
}

async function handle(request, response) {
  const host = request.headers.host || '127.0.0.1';
  const url = new URL(request.url, `http://${host}`);
  if (Date.now() - windowStart > 60_000) { windowStart = Date.now(); requests = 0; }
  if (++requests > 240) fail(429, 'Too many requests; try again later');

  if (request.method === 'GET' && url.pathname === '/health') return json(response, 200, { ok: true, store: 'none' });

  if (request.method === 'GET' && url.pathname === '/') return json(response, 200, { ok: true, store: 'none', service: 'ZenVoice MCP' });

  const origin = requireOrigin(url);
  const deviceMatch = /^\/d\/([^/]+)(\/.*)$/.exec(url.pathname);

  if (request.method === 'GET' && url.pathname === '/.well-known/oauth-authorization-server') {
    return json(response, 200, {
      issuer: origin,
      authorization_endpoint: `${origin}/authorize`,
      token_endpoint: `${origin}/token`,
      registration_endpoint: `${origin}/register`,
      revocation_endpoint: `${origin}/revoke`,
      code_challenge_methods_supported: ['S256'],
      grant_types_supported: ['authorization_code'],
      response_types_supported: ['code'],
      token_endpoint_auth_methods_supported: ['none', 'client_secret_post'],
      scopes_supported: ['meetings.read'],
    });
  }

  if (request.method === 'GET' && url.pathname === '/.well-known/oauth-protected-resource') {
    return json(response, 200, {
      resource: connectUrl(origin),
      authorization_servers: [origin],
      bearer_methods_supported: ['header'],
      scopes_supported: ['meetings.read'],
    });
  }

  if (request.method === 'POST' && url.pathname === '/register') {
    const input = await parseBody(request);
    const redirect = Array.isArray(input.redirect_uris) ? input.redirect_uris[0] : input.redirect_uris;
    if (typeof redirect !== 'string' || !/^https?:\/\//.test(redirect)) fail(400, 'redirect_uris required');
    const clientId = nonce();
    const clientSecret = nonce();
    clients.set(clientId, {
      secret: digest(clientSecret),
      name: typeof input.client_name === 'string' && input.client_name ? input.client_name.slice(0, 80) : 'AI tool',
      redirect,
    });
    return json(response, 201, {
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uris: [redirect],
      token_endpoint_auth_method: 'client_secret_post',
    });
  }

  if (request.method === 'POST' && url.pathname === '/device/register') {
    const input = await parseBody(request);
    if (input.id && input.secret) {
      const row = devices.get(input.id);
      if (!row || !equal(row.secret, digest(input.secret))) fail(401, 'Invalid device');
      if (!row.pairing) row.pairing = pairingOf();
      return json(response, 200, { id: input.id, pairing: row.pairing, mcpUrl: connectUrl(origin) });
    }
    const id = nonce().slice(0, 22);
    const secret = nonce();
    const pairing = pairingOf();
    devices.set(id, { secret: digest(secret), pairing });
    return json(response, 201, { id, secret, pairing, mcpUrl: connectUrl(origin) });
  }

  if (request.method === 'POST' && url.pathname === connectPath) {
    const token = bearer(request);
    if (!token) {
      response.writeHead(401, { 'www-authenticate': authWWW(origin), 'cache-control': 'no-store' });
      return response.end(JSON.stringify({ error: 'invalid_token' }));
    }
    const grant = tokens.get(digest(token));
    if (!grant || grant.expires < Date.now()) fail(401, 'Invalid or expired access token');
    const rpc = await parseBody(request);
    return proxyMcp(response, origin, grant.deviceId, rpc);
  }

  if (deviceMatch) {
    const deviceId = deviceMatch[1];
    const rest = deviceMatch[2];
    const row = device(deviceId);

    if (request.method === 'GET' && rest === '/.well-known/oauth-protected-resource') {
      return json(response, 200, {
        resource: connectUrl(origin),
        authorization_servers: [origin],
        bearer_methods_supported: ['header'],
        scopes_supported: ['meetings.read'],
      });
    }

    if (request.method === 'POST' && rest === '/pull') {
      if (!equal(digest(bearer(request)), row.secret)) fail(401, 'Invalid device');
      const queued = [...pending.entries()].find(([, value]) => value.deviceId === deviceId && value.waiting);
      if (queued) {
        queued[1].waiting = false;
        return json(response, 200, { requestId: queued[0], jsonrpc: queued[1].rpc });
      }
      const payload = await new Promise(resolve => {
        const timer = setTimeout(() => {
          pulls.delete(deviceId);
          resolve(null);
        }, waitMs());
        pulls.set(deviceId, { resolve, timer });
      });
      if (!payload) { response.writeHead(204); return response.end(); }
      return json(response, 200, payload);
    }

    if (request.method === 'POST' && rest === '/push') {
      if (!equal(digest(bearer(request)), row.secret)) fail(401, 'Invalid device');
      const input = await parseBody(request);
      const wait = pending.get(input.requestId);
      if (!wait || wait.deviceId !== deviceId) fail(404, 'Unknown request');
      pending.delete(input.requestId);
      clearTimeout(wait.timer);
      wait.resolve(input.response);
      return json(response, 200, { ok: true });
    }

    if (request.method === 'POST' && rest === '/revoke') {
      if (!equal(digest(bearer(request)), row.secret)) fail(401, 'Invalid device');
      for (const [token, value] of tokens) if (value.deviceId === deviceId) tokens.delete(token);
      return json(response, 200, { ok: true });
    }

    if (rest === '/mcp') {
      if (request.method !== 'POST') fail(405, 'POST required');
      const token = bearer(request);
      if (!token) {
        response.writeHead(401, { 'www-authenticate': authWWW(origin), 'cache-control': 'no-store' });
        return response.end(JSON.stringify({ error: 'invalid_token' }));
      }
      const grant = tokens.get(digest(token));
      if (!grant || grant.expires < Date.now() || grant.deviceId !== deviceId) fail(401, 'Invalid or expired access token');
      const rpc = await parseBody(request);
      return proxyMcp(response, origin, deviceId, rpc);
    }
  }

  if (request.method === 'GET' && url.pathname === '/authorize') {
    const clientId = url.searchParams.get('client_id') || '';
    const client = clients.get(clientId);
    if (!client) fail(400, 'Unknown client');
    const redirect = url.searchParams.get('redirect_uri') || '';
    if (redirect !== client.redirect) fail(400, 'redirect_uri mismatch');
    const challenge = url.searchParams.get('code_challenge') || '';
    if (!challenge) fail(400, 'PKCE code_challenge required');
    if ((url.searchParams.get('code_challenge_method') || 'S256') !== 'S256') fail(400, 'S256 required');
    const deviceId = resolveDevice(url);
    const state = url.searchParams.get('state') || '';
    const ticket = nonce();
    codes.set(ticket, { clientId, deviceId, challenge, redirect, state, expires: Date.now() + 600_000, kind: 'consent' });
    const page = html(
      'ZenVoice',
      '<h1>Allow this AI tool to read Notetaker meetings?</h1>' +
        '<p>Meetings stay on your Mac. This grant sends meeting text to the AI tool that requested access. Dictation is not included. Audio is not included. ZenVoice does not keep a copy.</p>' +
        '<form method="post" action="/authorize">' +
        '<input type="hidden" name="ticket" value="' + escape(ticket) + '">' +
        '<button name="decision" value="deny" type="submit">Deny</button>' +
        '<button name="decision" value="approve" type="submit">Approve</button>' +
        '</form>'
    );
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    return response.end(page);
  }

  if (request.method === 'POST' && url.pathname === '/authorize') {
    const input = await parseBody(request);
    const row = codes.get(input.ticket);
    if (!row || row.kind !== 'consent' || row.expires < Date.now()) fail(400, 'Invalid or expired consent');
    codes.delete(input.ticket);
    const target = new URL(row.redirect);
    if (input.decision !== 'approve') {
      target.searchParams.set('error', 'access_denied');
      if (row.state) target.searchParams.set('state', row.state);
      response.writeHead(302, { Location: target.href, 'cache-control': 'no-store' });
      return response.end();
    }
    const code = nonce();
    codes.set(code, { ...row, kind: 'code', expires: Date.now() + 60_000 });
    target.searchParams.set('code', code);
    if (row.state) target.searchParams.set('state', row.state);
    response.writeHead(302, { Location: target.href, 'cache-control': 'no-store' });
    return response.end();
  }

  if (request.method === 'POST' && url.pathname === '/token') {
    const input = await parseBody(request);
    const row = codes.get(input.code);
    if (!row || row.kind !== 'code' || row.expires < Date.now()) fail(400, 'Invalid or expired code');
    const client = clients.get(input.client_id || row.clientId);
    if (!client) fail(401, 'Unknown client');
    if (input.client_secret && !equal(digest(input.client_secret), client.secret)) fail(401, 'Invalid client');
    if (digest(input.code_verifier || '') !== row.challenge) fail(400, 'Invalid code_verifier');
    codes.delete(input.code);
    const access = nonce();
    tokens.set(digest(access), { deviceId: row.deviceId, clientId: row.clientId, expires: Date.now() + 3600_000 });
    return json(response, 200, { access_token: access, token_type: 'Bearer', expires_in: 3600, scope: 'meetings.read' });
  }

  if (request.method === 'POST' && url.pathname === '/revoke') {
    const input = await parseBody(request);
    if (input.token) tokens.delete(digest(input.token));
    return json(response, 200, { ok: true });
  }

  fail(404, 'Not found');
}

const server = http.createServer(async (request, response) => {
  try {
    await handle(request, response);
  } catch (error) {
    const status = error.status || 500;
    json(response, status, { error: error.message || 'Server error' });
  }
});
server.requestTimeout = 30_000;
server.headersTimeout = 10_000;
server.maxConnections = 128;

async function runCheck() {
  process.env.MCP_WAIT_MS = '400';
  process.env.PUBLIC_ORIGIN = '';
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  const origin = `http://127.0.0.1:${port}`;
  process.env.PUBLIC_ORIGIN = origin;
  const call = async (path, init = {}) => {
    const response = await fetch(origin + path, init);
    const text = await response.text();
    let body = {};
    try { body = text ? JSON.parse(text) : {}; } catch { body = { raw: text }; }
    return { status: response.status, headers: response.headers, body, text };
  };

  const registered = await call('/device/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
  assert.equal(registered.status, 201, 'device register');
  const { id, secret, pairing, mcpUrl } = registered.body;
  assert.equal(mcpUrl, `${origin}/connect/mcp`);
  assert.match(pairing, /^[A-Z0-9]{6}$/);
  const unauth = await call('/connect/mcp', { method: 'POST', body: '{}' });
  assert.equal(unauth.status, 401, 'mcp requires a token');
  assert.match(unauth.headers.get('www-authenticate') || '', /oauth-protected-resource/);

  const client = await call('/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ client_name: 'Check', redirect_uris: [`${origin}/done`] }),
  });
  assert.equal(client.status, 201);
  const verifier = nonce();
  const challenge = digest(verifier);
  const authorize = await call(`/authorize?client_id=${client.body.client_id}&redirect_uri=${encodeURIComponent(origin + '/done')}&code_challenge=${challenge}&code_challenge_method=S256&state=s&resource=${encodeURIComponent(mcpUrl)}&pairing=${pairing}`);
  assert.equal(authorize.status, 200);
  assert.match(authorize.text, /Approve/);
  const ticket = authorize.text.match(/name="ticket" value="([^"]+)"/)[1];
  const denied = await call('/authorize', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `ticket=${ticket}&decision=deny`, redirect: 'manual' });
  assert.equal(denied.status, 302);
  assert.match(denied.headers.get('location') || '', /access_denied/);

  const again = await call(`/authorize?client_id=${client.body.client_id}&redirect_uri=${encodeURIComponent(origin + '/done')}&code_challenge=${challenge}&code_challenge_method=S256&resource=${encodeURIComponent(mcpUrl)}&pairing=${pairing}`);
  const ticket2 = again.text.match(/name="ticket" value="([^"]+)"/)[1];
  const approved = await call('/authorize', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `ticket=${ticket2}&decision=approve`, redirect: 'manual' });
  const code = new URL(approved.headers.get('location')).searchParams.get('code');
  const token = await call('/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: client.body.client_id,
      client_secret: client.body.client_secret,
      code_verifier: verifier,
    }).toString(),
  });
  assert.equal(token.status, 200, 'token');
  const access = token.body.access_token;

  const pull = fetch(`${origin}/d/${id}/pull`, { method: 'POST', headers: { authorization: `Bearer ${secret}` } });
  await new Promise(resolve => setTimeout(resolve, 50));
  const mcp = fetch(mcpUrl, {
    method: 'POST',
    headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'list_meetings', arguments: {} } }),
  });
  const pulled = await pull;
  assert.equal(pulled.status, 200, 'device pull');
  const job = await pulled.json();
  assert.ok(job.requestId && job.jsonrpc);
  const pushed = await call(`/d/${id}/push`, {
    method: 'POST',
    headers: { authorization: `Bearer ${secret}`, 'content-type': 'application/json' },
    body: JSON.stringify({ requestId: job.requestId, response: { jsonrpc: '2.0', id: 1, result: { content: [{ type: 'text', text: '[]' }] } } }),
  });
  assert.equal(pushed.status, 200, 'device push');
  const mcpResult = await mcp;
  assert.equal(mcpResult.status, 200, 'mcp round trip');
  const mcpBody = await mcpResult.json();
  assert.equal(mcpBody.result.content[0].text, '[]');

  const offline = await call('/connect/mcp', {
    method: 'POST',
    headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
  });
  assert.equal(offline.status, 503, 'Mac offline');

  await call(`/d/${id}/revoke`, { method: 'POST', headers: { authorization: `Bearer ${secret}` } });
  const after = await call('/connect/mcp', {
    method: 'POST',
    headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
    body: '{}',
  });
  assert.equal(after.status, 401, 'revoked token rejected');

  server.close();
  console.log('PASS mcp relay: connect URL, pairing, OAuth PKCE, device tunnel, 401/503 fail-closed, revoke; no transcript store');
}

if (process.argv.includes('--check')) {
  runCheck().catch(error => { console.error(error); process.exit(1); });
} else {
  const port = Number(process.env.PORT ?? 8788);
  const host = process.env.HOST ?? '127.0.0.1';
  server.listen(port, host, () => console.log(`ZenVoice MCP relay ready on ${host}:${port}`));
}
