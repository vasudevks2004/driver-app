// Supabase generates and verifies OTPs. This hook only delivers its signed OTP.
export interface SmsConfig {
  enabled: boolean;
  hookSecret: string;
  msg91AuthKey: string;
  templateId: string;
  otpVariable: string;
  supabaseUrl: string;
  serviceKey: string;
}
const endpoint = 'https://control.msg91.com/api/v5/flow';
const responseHeaders = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
function result(status: number, message?: string): Response {
  return new Response(JSON.stringify(message ? { error: { http_code: status, message } } : {}), { status, headers: responseHeaders });
}
function base64(value: string): Uint8Array {
  const raw = atob(value); return Uint8Array.from(raw, c => c.charCodeAt(0));
}
async function hash(value: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(v => v.toString(16).padStart(2,'0')).join('');
}
async function verified(request: Request, body: string, secret: string): Promise<boolean> {
  const id = request.headers.get('webhook-id') ?? '';
  const timestamp = request.headers.get('webhook-timestamp') ?? '';
  const signatures = request.headers.get('webhook-signature') ?? '';
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id) || !/^\d{10,12}$/.test(timestamp) ||
      Math.abs(Date.now() / 1000 - Number(timestamp)) > 300 || signatures.length > 2048) return false;
  try {
    const keyBytes = base64(secret.replace(/^v1,/, '').replace(/^whsec_/, ''));
    if (keyBytes.length < 32) return false;
    const key = await crypto.subtle.importKey('raw', keyBytes as BufferSource, {name:'HMAC',hash:'SHA-256'}, false, ['verify']);
    const payload = new TextEncoder().encode(`${id}.${timestamp}.${body}`);
    for (const item of signatures.split(/\s+/)) {
      const [version, signature] = item.split(',');
      if (version === 'v1' && signature && await crypto.subtle.verify('HMAC',key,base64(signature) as BufferSource,payload)) return true;
    }
  } catch { /* Malformed signatures are rejected without leaking any data. */ }
  return false;
}
async function readBody(request: Request): Promise<string | null> {
  if (Number(request.headers.get('content-length') ?? 0) > 32768 || !request.body) return null;
  const reader = request.body.getReader(); const chunks: Uint8Array[] = []; let size = 0;
  while (true) {
    const {done,value} = await reader.read(); if (done) break;
    size += value.length;
    if (size > 32768) { await reader.cancel(); return null; }
    chunks.push(value);
  }
  const data = new Uint8Array(size); let offset=0;
  for (const chunk of chunks) { data.set(chunk,offset); offset+=chunk.length; }
  return new TextDecoder().decode(data);
}

export function createSmsHandler(config: SmsConfig, transport: typeof fetch = fetch): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    if (request.method !== 'POST') return result(405, 'Only signed SMS hook requests are accepted.');
    if (!config.hookSecret) return result(503, 'SMS sending has not been activated.');
    const raw = await readBody(request);
    if (raw == null) return result(413, 'SMS hook request is too large.');
    if (!await verified(request,raw,config.hookSecret)) return result(401, 'Invalid SMS hook signature.');
    if (!config.enabled || !config.msg91AuthKey || !/^[A-Za-z0-9_-]{1,100}$/.test(config.templateId) ||
        !/^[A-Za-z][A-Za-z0-9_]{0,39}$/.test(config.otpVariable) || config.otpVariable === 'mobiles' ||
        !config.supabaseUrl || !config.serviceKey) return result(503, 'SMS sending has not been activated.');
    let event;
    try { event = JSON.parse(raw); } catch { return result(400, 'Invalid SMS hook payload.'); }
    const phone = event?.user?.phone, otp = event?.sms?.otp;
    // The paid adapter intentionally serves Indian mobile numbers only.
    if (typeof phone !== 'string' || !/^\+?91[6-9]\d{9}$/.test(phone) ||
        typeof otp !== 'string' || !/^\d{6}$/.test(otp)) return result(400, 'A valid Indian mobile number and six-digit OTP are required.');
    const deadline = AbortSignal.timeout(4500);
    const dbHeaders = {apikey:config.serviceKey, Authorization:`Bearer ${config.serviceKey}`,
      'Content-Type':'application/json', Prefer:'return=representation'};
    const dbUrl = `${config.supabaseUrl.replace(/\/$/,'')}/rest/v1/driver_sms_delivery_receipts`;
    const fetch = (url: string, init: RequestInit) => transport(url,{...init,signal:deadline,redirect:'error'});
    let receiptId = '';
    try {
      receiptId = await hash(request.headers.get('webhook-id')!);
      const payloadHash = await hash(raw);
      const claim = await fetch(`${dbUrl}?on_conflict=id_hash`,{method:'POST',
        headers:{...dbHeaders,Prefer:'resolution=ignore-duplicates,return=representation'},
        body:JSON.stringify({id_hash:receiptId,payload_hash:payloadHash,status:'sending'})});
      if (!claim.ok) return result(503, 'SMS delivery is temporarily unavailable.');
      const claimed = await claim.json();
      if (!Array.isArray(claimed)) return result(503, 'SMS delivery is temporarily unavailable.');
      if (claimed.length === 0) {
        const previous = await fetch(`${dbUrl}?id_hash=eq.${receiptId}&select=status,payload_hash`,{method:'GET',headers:dbHeaders});
        if (!previous.ok) return result(503, 'SMS delivery is temporarily unavailable.');
        const rows = await previous.json();
        if (rows?.[0]?.payload_hash !== payloadHash) return result(409, 'This SMS request was already used.');
        return rows[0].status === 'sent' ? result(200) : result(503, 'This SMS request could not be completed. Request a new code after a minute.');
      }
      const provider = await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json',accept:'application/json',authkey:config.msg91AuthKey},
        body:JSON.stringify({template_id:config.templateId,short_url:'0',recipients:[{
          mobiles:phone.replace(/^\+/,''),[config.otpVariable]:otp,
        }]})});
      let data;
      try { data=await provider.json(); } catch { data=null; }
      const accepted=provider.ok && data?.type === 'success';
      const saved = await fetch(`${dbUrl}?id_hash=eq.${receiptId}`,{method:'PATCH',headers:dbHeaders,
        body:JSON.stringify({status:accepted?'sent':'failed',updated_at:new Date().toISOString()})});
      if (!saved.ok || !accepted) return result(503, 'The SMS provider could not accept this code. Please try again later.');
      return result(200);
    } catch {
      // Leave ambiguous deliveries reserved: a retry must never send a duplicate.
      // No OTPs, phone numbers, provider response bodies or API keys are logged.
      return result(503, 'SMS delivery took too long or is unavailable. Request a new code after a minute.');
    }
  };
}
