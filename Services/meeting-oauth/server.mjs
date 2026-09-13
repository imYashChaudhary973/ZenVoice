// OAuth codes only: this service never receives calendars, messages, transcripts, or audio.
// Deploy behind HTTPS. Provider client secrets remain in the server environment.
import http from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import assert from 'node:assert/strict';

const nonce = () => randomBytes(32).toString('base64url');
const digest = value => createHash('sha256').update(value).digest('base64url');
const flows = new Map();
const tickets = new Map();
const origin = process.env.PUBLIC_ORIGIN?.replace(/\/+$/, '');
// ponytail: per-process admission limit; use an edge limiter before scaling replicas.
let windowStart = Date.now(), requests = 0;
const providers = {
  gmail: { id: process.env.GOOGLE_CLIENT_ID, secret: process.env.GOOGLE_CLIENT_SECRET,
    authorize: 'https://accounts.google.com/o/oauth2/v2/auth', token: 'https://oauth2.googleapis.com/token',
    scope: 'https://www.googleapis.com/auth/gmail.readonly' },
  googleCalendar: { id: process.env.GOOGLE_CALENDAR_CLIENT_ID, secret: process.env.GOOGLE_CALENDAR_CLIENT_SECRET,
    authorize: 'https://accounts.google.com/o/oauth2/v2/auth', token: 'https://oauth2.googleapis.com/token',
    scope: 'https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly' },
  slack: { id: process.env.SLACK_CLIENT_ID, secret: process.env.SLACK_CLIENT_SECRET,
    authorize: 'https://slack.com/oauth/v2/authorize', token: 'https://slack.com/api/oauth.v2.access',
    scope: 'channels:read,groups:read,channels:history,groups:history' },
};
const validNonce = value => typeof value === 'string' && /^[A-Za-z0-9_-]{43,128}$/.test(value);
function fail(status, message) { throw Object.assign(new Error(message), { status }); }
function consume(ticket, verifier) {
  const flow = tickets.get(ticket);
  if (!flow || flow.expires < Date.now() || !validNonce(verifier)) fail(400, 'Invalid or expired handoff');
  const actual = Buffer.from(digest(verifier));
  const expected = Buffer.from(flow.challenge);
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) fail(400, 'Invalid handoff proof');
  tickets.delete(ticket);
  return flow;
}
async function exchange(provider, values) {
  const config = providers[provider];
  if (!config?.id || !config.secret) fail(503, 'Provider registration is not configured');
  const response = await fetch(config.token, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20_000),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: config.id, client_secret: config.secret, ...values }),
  });
  const result = await response.json();
  if (['invalid_grant', 'token_revoked', 'invalid_auth', 'account_inactive'].includes(result.error)) fail(401, 'Account access expired or was revoked');
  if (!response.ok || result.error || result.ok === false) fail(502, 'Provider rejected authorization. Reconnect or contact the workspace administrator.');
  const token = provider === 'slack' ? (result.authed_user ?? result) : result;
  if (typeof token.access_token !== 'string' || token.access_token.length > 8192) fail(502, 'Provider returned no user token');
  return { access_token: token.access_token, refresh_token: token.refresh_token ?? null,
    expires_in: token.expires_in ?? null, scope: token.scope ?? result.scope ?? '',
    account: provider === 'slack' ? `${result.team?.name ?? 'Slack'} / ${token.id ?? 'user'}` : provider === 'gmail' ? 'Gmail' : 'Google Calendar' };
}
async function body(request) {
  let bytes = 0; const chunks = [];
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > 16_384) fail(413, 'Request too large');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString()); } catch { fail(400, 'Invalid JSON'); }
}
function json(response, status, value) {
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' });
  response.end(JSON.stringify(value));
}
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    if (Date.now() - windowStart > 60_000) { windowStart = Date.now(); requests = 0; }
    if (++requests > 120) fail(429, 'Too many authorization requests; try again later');
    if (request.method === 'GET' && url.pathname === '/health') return json(response, 200, { ok: true });
    if (!origin || new URL(origin).protocol !== 'https:' || new URL(origin).origin !== origin) fail(503, 'A public HTTPS origin without a path is required');
    const provider = url.pathname.split('/').at(-1);
    if (request.method === 'GET' && url.pathname.startsWith('/authorize/')) {
      const config = providers[provider];
      if (!config?.id || !config.secret) fail(503, 'Provider registration is not configured');
      const state = url.searchParams.get('state'); const challenge = url.searchParams.get('challenge');
      if (!validNonce(state) || !validNonce(challenge)) fail(400, 'Invalid authorization request');
      if (flows.size + tickets.size >= 1000) fail(429, 'Authorization capacity reached; try again later');
      const serverState = nonce();
      const redirect = `${origin}/oauth/callback/${provider}`;
      flows.set(serverState, { provider, state, challenge, redirect, expires: Date.now() + 600_000 });
      const target = new URL(config.authorize);
      target.search = new URLSearchParams({ client_id: config.id, redirect_uri: redirect, state: serverState,
        ...(provider !== 'slack' ? { response_type: 'code', scope: config.scope, access_type: 'offline', prompt: 'consent',
          code_challenge: challenge, code_challenge_method: 'S256' } : { user_scope: config.scope }) });
      response.writeHead(302, { Location: target.href, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' });
      return response.end();
    }
    if (request.method === 'GET' && url.pathname.startsWith('/oauth/callback/')) {
      const state = url.searchParams.get('state'); const flow = flows.get(state);
      if (!flow || flow.provider !== provider || flow.expires < Date.now()) fail(400, 'Invalid or expired OAuth state');
      flows.delete(state);
      const code = url.searchParams.get('code');
      if (!code || code.length > 8192 || url.searchParams.has('error')) fail(400, 'Authorization was not granted');
      const ticket = nonce(); tickets.set(ticket, { ...flow, code, expires: Date.now() + 60_000 });
      const target = new URL('zenvoice-meeting://oauth/callback');
      target.search = new URLSearchParams({ ticket, state: flow.state });
      response.writeHead(302, { Location: target.href, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' });
      return response.end();
    }
    if (request.method === 'POST' && url.pathname === '/redeem') {
      const input = await body(request); const flow = consume(input.ticket, input.verifier);
      return json(response, 200, await exchange(flow.provider, { code: flow.code, redirect_uri: flow.redirect,
        ...(flow.provider !== 'slack' ? { grant_type: 'authorization_code', code_verifier: input.verifier } : {}) }));
    }
    if (request.method === 'POST' && url.pathname.startsWith('/refresh/')) {
      const input = await body(request);
      if (typeof input.refresh_token !== 'string' || input.refresh_token.length > 8192 || !input.refresh_token) fail(400, 'Invalid refresh token');
      return json(response, 200, await exchange(provider, { grant_type: 'refresh_token', refresh_token: input.refresh_token }));
    }
    fail(404, 'Not found');
  } catch (error) {
    // Do not echo upstream bodies, authorization codes, tokens, or request URLs.
    json(response, error.status ?? 500, { error: error.status ? error.message : 'Authorization service failed' });
  }
});
server.requestTimeout = 30_000;
server.maxConnections = 128;
server.headersTimeout = 10_000;
setInterval(() => { for (const map of [flows, tickets]) for (const [key, value] of map) if (value.expires < Date.now()) map.delete(key); }, 30_000).unref();
if (process.argv.includes('--check')) {
  const verifier = nonce(); const ticket = nonce();
  tickets.set(ticket, { challenge: digest(verifier), expires: Date.now() + 1000 });
  assert.throws(() => consume(ticket, nonce()));
  assert.ok(tickets.has(ticket), 'a wrong proof cannot destroy a valid handoff');
  consume(ticket, verifier);
  assert.throws(() => consume(ticket, verifier), 'handoffs are single-use');
  tickets.set(ticket, { challenge: digest(verifier), expires: Date.now() - 1 });
  assert.throws(() => consume(ticket, verifier), 'expired handoffs are rejected');
  console.log('PASS OAuth handoff: proof binding, single-use, expiry');
} else {
  server.listen(Number(process.env.PORT ?? 8787), process.env.HOST ?? '127.0.0.1', () => console.log('OAuth exchange service ready'));
}
