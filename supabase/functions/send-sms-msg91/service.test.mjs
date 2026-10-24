import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHmac } from 'node:crypto';
import { createSmsHandler } from './service.ts';

const key=Buffer.alloc(32,7);
const secret=`v1,whsec_${key.toString('base64')}`;
const body=JSON.stringify({user:{phone:'+919876543210'},sms:{otp:'123456'}});
function signed(raw=body, id='msg_fixture_001', timestamp=String(Math.floor(Date.now()/1000))) {
  const signature=createHmac('sha256',key).update(`${id}.${timestamp}.${raw}`).digest('base64');
  return {'Content-Type':'application/json','webhook-id':id,'webhook-timestamp':timestamp,'webhook-signature':`v1,${signature}`};
}
async function environment(run) {
  const rows=new Map(),calls=[]; let mode='success';
  const server=createServer(async(req,res)=>{
    const url=new URL(req.url,'http://local'); const chunks=[];
    for await(const chunk of req) chunks.push(chunk);
    const raw=Buffer.concat(chunks).toString();
    calls.push({path:url.pathname,method:req.method});
    const answer=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(data));};
    if(url.pathname==='/rest/v1/driver_sms_delivery_receipts') {
      if(req.method==='POST') {
        const row=JSON.parse(raw);
        if(rows.has(row.id_hash)) return answer([]);
        rows.set(row.id_hash,{...row}); return answer([row]);
      }
      const id=url.searchParams.get('id_hash')?.slice(3),row=rows.get(id);
      if(req.method==='GET') return answer(row?[row]:[]);
      if(row) Object.assign(row,JSON.parse(raw));
      return answer(row?[row]:[]);
    }
    if(url.pathname==='/api/v5/flow') {
      assert.equal(req.headers.authkey,'test-msg91-key');
      assert.equal(url.search,''); // OTPs and phone numbers are never put in URLs.
      const input=JSON.parse(raw);
      assert.equal(input.template_id,'test-approved-template');
      assert.deepEqual(input.recipients,[{mobiles:'919876543210',VAR1:'123456'}]);
      if(mode==='error') return answer({type:'error',message:'provider-internal-details'});
      if(mode==='html') {res.writeHead(503,{'Content-Type':'text/html'});res.end('<h1>secret-provider-body</h1>');return;}
      return answer({type:'success',message:'test-message-id'});
    }
    answer({message:'Unmodeled upstream'},501);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  const config={enabled:true,hookSecret:secret,msg91AuthKey:'test-msg91-key',templateId:'test-approved-template',otpVariable:'VAR1',supabaseUrl:base,serviceKey:'test-service-key'};
  const transport=(url,options)=>fetch(String(url).startsWith('https://control.msg91.com')?`${base}${new URL(url).pathname}`:url,options);
  const handler=createSmsHandler(config,transport);
  const call=(raw=body,headers=signed(raw))=>handler(new Request(`${base}/functions/v1/send-sms-msg91`,{method:'POST',headers,body:raw}));
  try{await run({call,config,rows,calls,setMode:(next)=>{mode=next;}});}
  finally{await new Promise(resolve=>server.close(resolve));}
}

test('signed Supabase OTP is delivered through real HTTP and replay does not bill twice',()=>environment(async e=>{
  assert.equal((await e.call()).status,200);
  assert.equal((await e.call()).status,200);
  assert.equal(e.calls.filter(x=>x.path==='/api/v5/flow').length,1);
  assert.equal([...e.rows.values()][0].status,'sent');
  const stored=JSON.stringify([...e.rows.values()]);
  assert.equal(stored.includes('123456'),false);
  assert.equal(stored.includes('919876543210'),false);
}));

test('concurrent delivery of the same signed event sends at most one SMS',()=>environment(async e=>{
  const results=await Promise.all([e.call(),e.call()]);
  assert.ok(results.some(x=>x.status===200));
  assert.equal(e.calls.filter(x=>x.path==='/api/v5/flow').length,1);
}));

test('forged, tampered and expired hooks make no upstream HTTP calls',()=>environment(async e=>{
  assert.equal((await e.call(body,{...signed(),'webhook-signature':'v1,invalid'})).status,401);
  assert.equal((await e.call(body.replace('123456','654321'),signed())).status,401);
  assert.equal((await e.call(body,signed(body,'msg_old',String(Math.floor(Date.now()/1000)-301)))).status,401);
  assert.equal(e.calls.length,0);
}));

test('missing activation or invalid country fails before contacting the paid provider',()=>environment(async e=>{
  e.config.enabled=false;
  assert.equal((await e.call()).status,503);
  e.config.enabled=true;
  const foreign=JSON.stringify({user:{phone:'+16505551234'},sms:{otp:'123456'}});
  assert.equal((await e.call(foreign)).status,400);
  assert.equal(e.calls.length,0);
}));

test('MSG91 HTTP 200 error bodies fail authentication and cannot be mistaken for delivery',()=>environment(async e=>{
  e.setMode('error');
  const failure=await e.call();assert.equal(failure.status,503);
  assert.equal((await failure.text()).includes('provider-internal-details'),false);
  assert.equal((await e.call()).status,503);
  assert.equal(e.calls.filter(x=>x.path==='/api/v5/flow').length,1);
}));

test('HTML provider outages are redacted and large unsigned requests are bounded',()=>environment(async e=>{
  e.setMode('html'); const failure=await e.call();
  assert.equal(failure.status,503);assert.equal((await failure.text()).includes('secret-provider-body'),false);
  assert.equal((await e.call('x'.repeat(32769))).status,413);
}));
