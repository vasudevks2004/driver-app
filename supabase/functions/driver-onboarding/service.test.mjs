import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHandler, governmentUrl } from './service.ts';

const userId = '11111111-1111-4111-8111-111111111111';
const otherId = '22222222-2222-4222-8222-222222222222';
const appId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const jpeg = Buffer.from([255,216,255,224,1,2,3,4]);

async function environment(run) {
  const rows = new Map(), oauth = new Map(), objects = new Map(), calls = [];
  let providerDenied = false;
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://local');
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const raw = Buffer.concat(chunks); const method = req.method;
    calls.push({method, path: url.pathname});
    const respond = (value, status = 200) => { res.writeHead(status, {'Content-Type':'application/json'}); res.end(JSON.stringify(value)); };
    if (url.pathname === '/auth/v1/user') {
      if (req.headers.authorization === 'Bearer invalid') return respond({},401);
      return respond({id: req.headers.authorization === 'Bearer other' ? otherId : userId,
        phone: '919876543210', phone_confirmed_at: '2026-01-01T00:00:00Z', is_anonymous: false});
    }
    if (url.pathname === '/rest/v1/driver_applications') {
      const owner = url.searchParams.get('user_id')?.slice(3);
      const id = url.searchParams.get('id')?.slice(3);
      const selected = [...rows.values()].filter(row => (!owner || owner === row.user_id) && (!id || id === row.id) &&
        (!url.searchParams.has('status') || row.status === url.searchParams.get('status').slice(3)));
      if (method === 'GET') return respond(selected);
      const input = JSON.parse(raw);
      if (method === 'POST') { if (!rows.has(input.user_id)) rows.set(input.user_id,{id:appId,status:'draft',digilocker_status:'not_connected',...input}); return respond([]); }
      for (const row of selected) Object.assign(row,input);
      return respond(selected);
    }
    if (url.pathname === '/rest/v1/driver_digilocker_requests') {
      const hash = url.searchParams.get('state_hash')?.slice(3);
      let selected = [...oauth.values()].filter(row => (!hash || row.state_hash === hash) &&
        (!url.searchParams.has('consumed_at') || row.consumed_at == null) &&
        (!url.searchParams.has('expires_at') || row.expires_at > url.searchParams.get('expires_at').slice(3)));
      if (method === 'DELETE') { for(const row of selected) oauth.delete(row.state_hash); return respond(selected); }
      const input = JSON.parse(raw);
      if (method === 'POST') { oauth.set(input.state_hash,{...input}); return respond([input]); }
      const before = selected.map(x => ({...x}));
      for(const row of selected) Object.assign(row,input);
      return respond(before.map((row) => ({...row,...input})));
    }
    if (url.pathname.startsWith('/storage/v1/object/')) {
      objects.set(url.pathname,{bytes:raw,mime:req.headers['content-type']}); return respond({Key:url.pathname});
    }
    if (url.pathname === '/oauth/token') {
      const form = new URLSearchParams(raw.toString());
      assert.equal(form.get('grant_type'),'authorization_code');
      assert.equal(form.get('code_verifier').length,43);
      if (providerDenied) return respond({error:'invalid_grant'},400);
      return respond({access_token:'provider-access-token'});
    }
    if (url.pathname === '/issued') return respond({items:[{doctype:'DRVLC',uri:'in.gov.transport-DRVLC-12345'}]});
    if (url.pathname.startsWith('/file/')) { res.writeHead(200,{'Content-Type':'application/pdf'}); res.end('%PDF-1.7 issued licence test fixture'); return; }
    return respond({message:'Unmodeled upstream endpoint'},501);
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const config = {supabaseUrl:base,serviceKey:'test-service-key',digiLocker:{clientId:'test-client',clientSecret:'test-secret',
    redirectUri:`${base}/functions/v1/driver-onboarding/digilocker/callback`,authorizationUrl:'https://digilocker.gov.in/oauth/authorize',
    tokenUrl:'https://digilocker.gov.in/oauth/token',issuedDocumentsUrl:'https://digilocker.gov.in/issued',
    documentUrlTemplate:'https://digilocker.gov.in/file/{uri}',scope:''}};
  // Route official provider hosts to a real local HTTP stand-in; no HTTP client stubs.
  const proxy = async (url, options) => {
    const u = new URL(url); return fetch(u.hostname === 'digilocker.gov.in' ? `${base}${u.pathname}${u.search}` : url,options);
  };
  const handler = createHandler(config,proxy);
  const call = (path, {method='GET',body,token='applicant',mime='application/json'} = {}) => handler(new Request(
    `${base}/functions/v1/driver-onboarding${path}`,{method,headers:{Authorization:`Bearer ${token}`,'Content-Type':mime},
      body: body === undefined ? undefined : Buffer.isBuffer(body) ? body : JSON.stringify(body)}));
  const open = async () => { const result = await call('/application',{method:'POST',body:{full_name:'Test Driver',city:'Kochi'}}); assert.equal(result.status,200); return result.json(); };
  try { await run({call,open,rows,oauth,objects,calls,config,handler,denyProvider:()=>{providerDenied=true;}}); }
  finally { await new Promise(resolve=>server.close(resolve)); }
}

test('manual registration validates ownership, private images, consent and submission', async()=> environment(async e=>{
  assert.equal((await e.call('/application',{token:'invalid'})).status,401);
  await e.open();
  assert.equal((await e.call('/application',{token:'other'})).status,404);
  const fields={licence_number:'KL07 20201234567',birth_date:'1995-01-15',licence_expiry:'2035-01-15',vehicle_class:'LMV',consent:true};
  assert.equal((await e.call('/submit',{method:'POST',body:fields})).status,400);
  assert.equal((await e.call('/documents/selfie',{method:'POST',body:Buffer.from('not an image'),mime:'image/jpeg'})).status,400);
  for(const kind of ['selfie','licence_front','licence_back']) {
    assert.equal((await e.call(`/documents/${kind}`,{method:'POST',body:jpeg,mime:'image/jpeg'})).status,200);
  }
  assert.equal(e.objects.size,3);
  assert.equal((await e.call('/submit',{method:'POST',body:{...fields,consent:false}})).status,400);
  const submitted=await e.call('/submit',{method:'POST',body:fields});
  assert.equal((await submitted.json()).status,'submitted');
  assert.equal((await e.call('/documents/selfie',{method:'POST',body:jpeg,mime:'image/jpeg'})).status,409);
  assert.equal((await e.call('/submit',{method:'POST',body:fields})).status,200);
  assert.ok(e.calls.some(c=>c.path==='/auth/v1/user'));
  assert.ok(e.calls.some(c=>c.path.startsWith('/storage/v1/object/driver-onboarding-private/')));
}));

test('DigiLocker consent uses PKCE and single-use state; document receipt never approves driver',async()=> environment(async e=>{
  await e.open();
  const started=await e.call('/digilocker/start',{method:'POST',body:{consent:true}});
  const auth=new URL((await started.json()).authorization_url);
  assert.equal(auth.searchParams.get('code_challenge_method'),'S256');
  assert.equal(auth.searchParams.get('code_challenge').length,43);
  const state=auth.searchParams.get('state');
  assert.notEqual([...e.oauth.keys()][0],state);
  const callback=`/digilocker/callback?state=${state}&code=test-code`;
  assert.equal((await e.call(callback)).status,200);
  const application=await (await e.call('/application')).json();
  assert.equal(application.digilocker_status,'document_received');
  assert.equal(application.status,'draft');
  assert.equal((await e.call(callback)).status,400);
  assert.equal(e.calls.filter(c=>c.path==='/oauth/token').length,1);
  assert.equal([...e.oauth.values()][0].code_verifier,null);
}));

test('canceled, failed and expired DigiLocker sessions never count as document verification',async()=> environment(async e=>{
  await e.open();
  const start=async()=>new URL((await (await e.call('/digilocker/start',{method:'POST',body:{consent:true}})).json()).authorization_url).searchParams.get('state');
  let state=await start();
  assert.equal((await e.call(`/digilocker/callback?state=${state}&error=access_denied`)).status,400);
  assert.equal(e.rows.get(userId).digilocker_status,'failed');
  state=await start(); e.denyProvider();
  assert.equal((await e.call(`/digilocker/callback?state=${state}&code=test`)).status,400);
  assert.equal(e.rows.get(userId).digilocker_status,'failed');
  state=await start(); for(const row of e.oauth.values()) row.expires_at='2000-01-01T00:00:00Z';
  assert.equal((await e.call(`/digilocker/callback?state=${state}&code=test`)).status,400);
  assert.equal(e.rows.get(userId).digilocker_document_path,undefined);
}));

test('unconfigured DigiLocker gives honest setup message and rejects arbitrary provider URLs', async()=>environment(async e=>{
  await e.open(); e.config.digiLocker.clientSecret='';
  const result=await e.call('/digilocker/start',{method:'POST',body:{consent:true}});
  assert.equal(result.status,503);
  assert.match((await result.json()).message,/upload your licence photos/);
  assert.equal(governmentUrl('https://digilocker.gov.in.evil.example/oauth'),false);
  assert.equal(governmentUrl('http://digilocker.gov.in/oauth'),false);
  assert.equal(governmentUrl('https://digilocker.gov.in:444/oauth'),false);
  assert.equal(governmentUrl('https://digilocker.meripehchaan.gov.in/public/oauth2/1/authorize'),true);
}));
