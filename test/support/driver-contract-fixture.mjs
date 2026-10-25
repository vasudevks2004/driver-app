// Public, test-only HTTP stand-in for the documented driver API.
// It checks client encoding/recovery only. Real SQL, Worker, Auth authorization and
// financial constraints are tested separately in the private shared repository.
import http from 'node:http';
const cases=new Map(),tokens=new Map(),receipts=new Map(),requests=[];let fault=null,objects=0,files=0,refreshCount=0;
const json=(res,status,value)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
const server=http.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1'),path=url.pathname,chunks=[];for await(const chunk of req)chunks.push(chunk);const bytes=Buffer.concat(chunks);
 const body=()=>bytes.length?JSON.parse(bytes):{},ok=value=>json(res,200,value),data=value=>ok({data:value}),deny=(message,status=400)=>json(res,status,{error:{message}});
 if(path==='/__case'){
  const c={id:crypto.randomUUID(),tripId:crypto.randomUUID(),token:crypto.randomUUID(),refreshToken:crypto.randomUUID(),code:String(crypto.getRandomValues(new Uint32Array(1))[0]%1000000).padStart(6,'0'),selfie:false,expensesSubmitted:false,noExpenses:false,expenses:0,journals:0,status:'assigned'};
  c.profile={id:c.id,role:'driver',name:'Contract Driver',mustChangePassword:false};cases.set(c.tripId,c);tokens.set(c.token,c);return ok(c);
 }
 if(path==='/__fault'){fault=body();return ok({ok:true});}
 if(path==='/__state'){const c=cases.get(url.searchParams.get('tripId'));return ok({expenses:c.expenses,journals:c.journals,objects,files,refreshCount,requests});}
 if(path==='/__code')return ok({code:cases.get(body().tripId).code});
 if(path.endsWith('/auth/driver/refresh')){const c=[...cases.values()].find(c=>c.refreshToken===body().refreshToken);if(!c)return deny('Expired session',401);refreshCount++;tokens.delete(c.token);c.token=crypto.randomUUID();tokens.set(c.token,c);return data({token:c.token,refreshToken:c.refreshToken,expiresIn:3600,profile:c.profile});}
 const c=tokens.get(req.headers.authorization?.replace(/^Bearer /,''));if(!c)return deny('Expired session',401);
 const target=/\/trips\/([0-9a-f-]{36})/.exec(path);if(target&&target[1]!==c.tripId)return deny('Not assigned to this driver',403);
 requests.push({path,method:req.method,mime:req.headers['content-type'],key:req.headers['idempotency-key'],filename:req.headers['x-filename'],expiry:req.headers['x-expires-on']});
 const duty=()=>({id:c.tripId,status:c.status,company:'Contract Business',pickup:'Kochi',drop:'Aluva',selfie:c.selfie,expensesSubmitted:c.expensesSubmitted,noExpenses:c.noExpenses,expenses:[]});
 if(req.method==='GET'){
  const receipt=/\/operations\/([0-9a-f-]{36})$/.exec(path);if(receipt)return data({committed:[...receipts.keys()].some(k=>k.startsWith(c.id+':')&&k.endsWith(':'+receipt[1]))});
  if(path.endsWith('/wallet'))return data({balance:c.journals?70.09:0,meaning:'outstanding_payable',transactions:c.journals?[{id:'journal',kind:'trip_credit',signedAmount:70.09,amount:70.09}]:[],nextCursor:null});
  if(target)return data(duty());if(path.endsWith('/drivers/me'))return data(c.profile);return data({trips:[duty()],activeCount:1,completedCount:0,nextCursor:null});
 }
 const key=req.headers['idempotency-key'];if(!/^[0-9a-f-]{36}$/.test(key||''))return deny('Retry key required');
 const signature=c.id+':'+path+':'+key;if(receipts.has(signature))return data(receipts.get(signature));
 if(path.endsWith('/selfie')){
  if(req.headers['content-type']!=='image/jpeg'||bytes[0]!==255||bytes[1]!==216)return deny('Photo required',415);
  if(!req.headers['x-filename']||bytes.length>5242880)return deny('Invalid upload',413);c.selfie=true;files++;objects++;
 }else if(path.endsWith('/start'))c.status='ongoing';
 else if(path.endsWith('/expenses')){c.expensesSubmitted=true;c.noExpenses=Number(body().amount)===0;if(!c.noExpenses)c.expenses++;}
 else if(path.endsWith('/close')){if(!c.selfie||!c.expensesSubmitted||body().otp!==c.code)return deny('Selfie, expenses and partner code required');c.status='closed';c.journals=1;}
 const receipt={ok:true};receipts.set(signature,receipt);
 if(fault&&path.endsWith(fault.suffix)){const disconnect=fault.disconnect;fault=null;if(disconnect){res.destroy();return;}return deny('Injected lost acknowledgement',503);}return data(receipt);
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));process.stdout.write(JSON.stringify({base:'http://127.0.0.1:'+server.address().port})+'\n');
process.on('SIGTERM',()=>{server.closeAllConnections();server.close(()=>process.exit(0));});
