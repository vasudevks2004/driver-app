// No provider secrets/tokens are sent to the app or written to logs.
export interface DigiLockerConfig {
  clientId: string; clientSecret: string; redirectUri: string;
  authorizationUrl: string; tokenUrl: string; issuedDocumentsUrl: string;
  documentUrlTemplate: string; scope: string;
}
export interface Config {
  supabaseUrl: string; serviceKey: string; digiLocker: DigiLockerConfig;
}
type Row = Record<string, unknown>;
const bucket = 'driver-onboarding-private';
const maxBytes = 6 * 1024 * 1024;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Cache-Control': 'no-store' };
class PublicError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
function callbackPage(ok: boolean): Response {
  return new Response(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HireD · DigiLocker</title><body style="font:18px system-ui;max-width:520px;margin:70px auto;padding:24px;color:#202331"><h1>HireD</h1><h2>${ok ? 'Licence received' : 'Connection did not finish'}</h2><p>${ok ? 'Return to HireD and check your connection. Your application still needs HireD review.' : 'Return to HireD to try again or upload your licence photos.'}</p></body></html>`,
    { status: ok ? 200 : 400, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'", 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' } });
}
function imageType(bytes: Uint8Array): string | null {
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'image/jpeg';
  const png = [137,80,78,71,13,10,26,10];
  return bytes.length >= 8 && png.every((v, i) => bytes[i] === v) ? 'image/png' : null;
}
function snapshot(row: Row): Row {
  return { id: row.id, status: row.status, full_name: row.full_name, city: row.city,
    selfie_uploaded: !!row.selfie_path, licence_front_uploaded: !!row.licence_front_path,
    licence_back_uploaded: !!row.licence_back_path, digilocker_status: row.digilocker_status,
    submitted_at: row.submitted_at };
}
function text(value: unknown, min: number, max: number): string {
  if (typeof value !== 'string' || value.trim().length < min || value.trim().length > max) throw new PublicError(400, 'Check your application details.');
  return value.trim();
}
export function governmentUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && (!url.port || url.port === '443') && !url.username && !url.password &&
      [ 'digilocker.gov.in', 'meripehchaan.gov.in' ].some(d => url.hostname === d || url.hostname.endsWith(`.${d}`));
  } catch { return false; }
}
export function digiLockerConfigured(config: DigiLockerConfig): boolean {
  return !!(config.clientId && config.clientSecret && config.redirectUri &&
    config.documentUrlTemplate.includes('{uri}') &&
    [config.authorizationUrl, config.tokenUrl, config.issuedDocumentsUrl,
      config.documentUrlTemplate.replace('{uri}', 'test')].every(governmentUrl));
}
const b64url = (data: Uint8Array) => btoa(String.fromCharCode(...data)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
async function digest(input: string): Promise<string> {
  return b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))));
}
async function limitedBytes(response: Response | Request, limit = maxBytes): Promise<Uint8Array> {
  const length = Number(response.headers.get('content-length') ?? 0);
  if (length > limit) throw new PublicError(413, 'Choose an image smaller than 6 MB.');
  if (!response.body) throw new PublicError(400, 'The image is empty.');
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = []; let size = 0;
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.length;
    if (size > limit) { await reader.cancel(); throw new PublicError(413, 'Choose an image smaller than 6 MB.'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

export function createHandler(config: Config, transport: typeof fetch = fetch): (request: Request) => Promise<Response> {
  const origin = config.supabaseUrl.replace(/\/$/, '');
  const headers = { apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`, 'Content-Type': 'application/json' };
  async function request(url: string, init: RequestInit = {}): Promise<Response> {
    return await transport(url, { ...init, redirect: 'error', signal: AbortSignal.timeout(20000) });
  }
  async function db(tableAndQuery: string, method = 'GET', body?: unknown): Promise<Row[]> {
    const response = await request(`${origin}/rest/v1/${tableAndQuery}`, { method,
      headers: { ...headers, Prefer: 'return=representation' }, body: body === undefined ? undefined : JSON.stringify(body) });
    if (!response.ok) throw new PublicError(503, 'Registration is temporarily unavailable. Please retry.');
    return await response.json() as Row[];
  }
  async function application(userId: string): Promise<Row> {
    const rows = await db(`driver_applications?user_id=eq.${encodeURIComponent(userId)}&limit=1`);
    if (!rows.length) throw new PublicError(404, 'Start your driver application first.');
    return rows[0];
  }
  async function update(app: Row, values: Row): Promise<Row> {
    const rows = await db(`driver_applications?id=eq.${app.id}&status=eq.draft`, 'PATCH', values);
    if (!rows.length) throw new PublicError(409, 'This application has already been submitted.');
    return rows[0];
  }
  async function upload(path: string, bytes: Uint8Array, mime: string): Promise<void> {
    const response = await request(`${origin}/storage/v1/object/${bucket}/${path}`, {
      method: 'POST', headers: { ...headers, 'Content-Type': mime, 'x-upsert': 'true' }, body: bytes as BodyInit });
    if (!response.ok) throw new PublicError(503, 'The image could not be uploaded. Please retry.');
  }
  async function body(request: Request): Promise<Row> {
    // JSON fields are small. Images use the bounded streaming route separately.
    if (Number(request.headers.get('content-length') ?? 0) > 4096) throw new PublicError(413, 'Request is too large.');
    const raw = new TextDecoder().decode(await limitedBytes(request, 4096));
    if (raw.length > 4096) throw new PublicError(413, 'Request is too large.');
    try { const data = JSON.parse(raw); if (!data || Array.isArray(data) || typeof data !== 'object') throw new Error(); return data; }
    catch { throw new PublicError(400, 'Check your application details.'); }
  }
  async function callback(url: URL): Promise<Response> {
    const state = url.searchParams.get('state') ?? '';
    if (!/^[A-Za-z0-9_-]{43}$/.test(state)) return callbackPage(false);
    const stateHash = await digest(state);
    // A conditional UPDATE atomically consumes state. A replay cannot redeem a code.
    const rows = await db(`driver_digilocker_requests?state_hash=eq.${stateHash}&consumed_at=is.null&expires_at=gt.${encodeURIComponent(new Date().toISOString())}`, 'PATCH', { consumed_at: new Date().toISOString() });
    if (!rows.length) return callbackPage(false);
    const session = rows[0];
    await db(`driver_digilocker_requests?state_hash=eq.${stateHash}`, 'PATCH', { code_verifier: null });
    let app: Row;
    try {
      app = await application(String(session.user_id));
      if (app.id !== session.application_id || app.status !== 'draft') return callbackPage(false);
      if (url.searchParams.has('error')) throw new Error('User canceled');
      const code = text(url.searchParams.get('code'), 1, 2048);
      const c = config.digiLocker;
      const tokenResponse = await request(c.tokenUrl, { method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'authorization_code', code, client_id: c.clientId,
          client_secret: c.clientSecret, redirect_uri: c.redirectUri, code_verifier: String(session.code_verifier) }) });
      if (!tokenResponse.ok) throw new Error('Token exchange failed');
      const token = await tokenResponse.json();
      if (typeof token.access_token !== 'string' || !token.access_token) throw new Error('Missing provider token');
      const documentsResponse = await request(c.issuedDocumentsUrl, { headers: { Authorization: `Bearer ${token.access_token}` } });
      if (!documentsResponse.ok) throw new Error('Documents unavailable');
      const documents = await documentsResponse.json();
      const items = Array.isArray(documents.items) ? documents.items : [];
      // Only issuer-provided driving licences; never DigiLocker user uploads.
      const licence = items.find((item: Row) => item.doctype === 'DRVLC' && typeof item.uri === 'string');
      if (!licence || licence.uri.length > 1024) throw new Error('No issued driving licence');
      const documentResponse = await request(c.documentUrlTemplate.replace('{uri}', encodeURIComponent(licence.uri)), {
        headers: { Authorization: `Bearer ${token.access_token}` } });
      if (!documentResponse.ok) throw new Error('Document unavailable');
      const bytes = await limitedBytes(documentResponse);
      const isPdf = new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-';
      const mime = isPdf ? 'application/pdf' : imageType(bytes);
      if (!mime) throw new Error('Unsupported issued document');
      const path = `${session.user_id}/${app.id}/digilocker-licence-${crypto.randomUUID()}.${isPdf ? 'pdf' : mime === 'image/png' ? 'png' : 'jpg'}`;
      await upload(path, bytes, mime);
      await update(app, { digilocker_document_path: path, digilocker_document_uri: licence.uri, digilocker_status: 'document_received' });
      return callbackPage(true);
    } catch {
      // Never expose provider bodies, document data, state or tokens in errors.
      await db(`driver_applications?id=eq.${session.application_id}&status=eq.draft`, 'PATCH', { digilocker_status: 'failed' });
      return callbackPage(false);
    }
  }

  return async (req: Request): Promise<Response> => {
    const url = new URL(req.url);
    const route = url.pathname.split('/driver-onboarding').at(-1) || '/';
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    try {
      if (route === '/digilocker/callback' && req.method === 'GET') {
        if (!digiLockerConfigured(config.digiLocker)) return callbackPage(false);
        return await callback(url);
      }
      if (!origin || !config.serviceKey) throw new PublicError(503, 'Registration is being set up. Please try again later.');
      const authorization = req.headers.get('Authorization') ?? '';
      if (!authorization.startsWith('Bearer ') || authorization.length > 8192) throw new PublicError(401, 'Verify your mobile number to continue.');
      const identityResponse = await request(`${origin}/auth/v1/user`, { headers: { apikey: config.serviceKey, Authorization: authorization } });
      if (!identityResponse.ok) throw new PublicError(401, 'Your verification session expired. Sign in again.');
      const user = await identityResponse.json();
      if (!/^[0-9a-f-]{36}$/i.test(user.id) || !user.phone_confirmed_at || !user.phone || user.is_anonymous === true) throw new PublicError(403, 'Verify your mobile number to submit a driver application.');
      if (route === '/application' && req.method === 'POST') {
        const input = await body(req);
        const fullName = text(input.full_name, 2, 100), city = text(input.city, 2, 80);
        const existing = await db(`driver_applications?user_id=eq.${user.id}&limit=1`);
        if (existing.length) return json(snapshot(existing[0]));
        // Unique user_id plus ignore-duplicates makes concurrent starts harmless.
        const response = await request(`${origin}/rest/v1/driver_applications?on_conflict=user_id`, { method: 'POST',
          headers: { ...headers, Prefer: 'resolution=ignore-duplicates,return=representation' },
          body: JSON.stringify({ user_id: user.id, full_name: fullName, city, verified_phone: user.phone }) });
        if (!response.ok) throw new PublicError(503, 'Could not start your application. Please retry.');
        return json(snapshot(await application(user.id)));
      }
      if (route === '/application' && req.method === 'GET') return json(snapshot(await application(user.id)));
      const app = await application(user.id);
      if (route === '/avatar' && req.method === 'GET') {
        if (!app.selfie_path) throw new PublicError(404, 'No profile photo has been uploaded.');
        const image = await request(`${origin}/storage/v1/object/authenticated/${bucket}/${app.selfie_path}`, { headers });
        if (!image.ok) throw new PublicError(404, 'Profile photo is unavailable.');
        const bytes = await limitedBytes(image), mime = imageType(bytes);
        if (!mime) throw new PublicError(404, 'Profile photo is unavailable.');
        return new Response(bytes as BodyInit, { headers: { ...cors, 'Content-Type': mime, 'X-Content-Type-Options': 'nosniff' } });
      }
      if (route === '/submit' && req.method === 'POST' && app.status === 'submitted') return json(snapshot(app));
      if (app.status !== 'draft') throw new PublicError(409, 'This application has already been submitted.');
      if (route.startsWith('/documents/') && req.method === 'POST') {
        const kind = route.substring('/documents/'.length);
        if (!['selfie', 'licence_front', 'licence_back'].includes(kind)) throw new PublicError(400, 'Choose a supported document.');
        const bytes = await limitedBytes(req), mime = imageType(bytes);
        if (!mime || req.headers.get('content-type') !== mime) throw new PublicError(400, 'Choose a JPG or PNG image.');
        const path = `${user.id}/${app.id}/${kind}-${crypto.randomUUID()}.${mime === 'image/png' ? 'png' : 'jpg'}`;
        await upload(path, bytes, mime);
        return json(snapshot(await update(app, { [`${kind}_path`]: path })));
      }
      if (route === '/digilocker/start' && req.method === 'POST') {
        if (!digiLockerConfigured(config.digiLocker)) throw new PublicError(503, 'DigiLocker is being set up. You can upload your licence photos instead.');
        const input = await body(req);
        if (input.consent !== true) throw new PublicError(400, 'Permission is required to connect DigiLocker.');
        const c = config.digiLocker;
        const expectedCallback = `${origin}/functions/v1/driver-onboarding/digilocker/callback`;
        if (c.redirectUri !== expectedCallback) throw new PublicError(503, 'DigiLocker is being set up. Please use licence photos for now.');
        // Invalidate earlier unused requests for this applicant and remove verifiers.
        await db(`driver_digilocker_requests?user_id=eq.${user.id}&consumed_at=is.null`, 'DELETE');
        const state = b64url(crypto.getRandomValues(new Uint8Array(32)));
        const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
        await db('driver_digilocker_requests', 'POST', { state_hash: await digest(state), application_id: app.id,
          user_id: user.id, code_verifier: verifier, expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString() });
        await update(app, { digilocker_status: 'pending' });
        const auth = new URL(c.authorizationUrl);
        for (const [key, value] of Object.entries({response_type: 'code', client_id: c.clientId,
          redirect_uri: c.redirectUri, state, code_challenge: await digest(verifier), code_challenge_method: 'S256'})) auth.searchParams.set(key, value);
        if (c.scope) auth.searchParams.set('scope', c.scope);
        return json({ authorization_url: auth.toString() });
      }
      if (route === '/submit' && req.method === 'POST') {
        const input = await body(req);
        const number = text(input.licence_number, 6, 30).toUpperCase();
        if (!/^[A-Z0-9][A-Z0-9 /-]{5,29}$/.test(number) || !/[0-9]/.test(number)) throw new PublicError(400, 'Check your driving licence number.');
        const date = (value: unknown): string => {
          if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0,10) !== value) throw new PublicError(400, 'Check your document dates.');
          return value;
        };
        const birth = date(input.birth_date), expiry = date(input.licence_expiry), today = new Date().toISOString().slice(0,10);
        if (birth < '1900-01-01' || birth >= today || expiry < today || !['LMV','TRANSPORT','BOTH'].includes(String(input.vehicle_class))) throw new PublicError(400, 'Check your licence details and expiry.');
        if (!app.selfie_path || (!app.digilocker_document_path && (!app.licence_front_path || !app.licence_back_path))) throw new PublicError(400, 'Add your selfie and both licence photos, or share your licence through DigiLocker.');
        if (input.consent !== true) throw new PublicError(400, 'Agree to document review and profile photo use before submitting.');
        return json(snapshot(await update(app, { birth_date: birth, licence_number: number, licence_expiry: expiry,
          vehicle_class: input.vehicle_class, status: 'submitted', consent_version: 'driver-onboarding-v1',
          consented_at: new Date().toISOString(), submitted_at: new Date().toISOString() })));
      }
      return json({message: 'Endpoint not found.'}, 404);
    } catch (error) {
      return error instanceof PublicError ? json({ message: error.message }, error.status)
        : json({ message: 'Registration is temporarily unavailable. Please retry.' }, 503);
    }
  };
}
