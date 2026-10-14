// Server-only Razorpay TEST integration. Service-role and payment secrets never enter the browser.
const j=(data,status=200,headers={})=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json',...headers}});
export async function hmac(secret,value){const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(value)))).map(x=>x.toString(16).padStart(2,'0')).join('');}
export function same(a,b){if(typeof a!=='string'||typeof b!=='string'||a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}
export function validateCaptured(payment,order,booking){return payment.status==='captured'&&payment.order_id===order.order_id&&payment.amount===booking.total_paise&&payment.currency==='INR';}
export async function handler(req,env){
 const site=env.SITE_ORIGIN,origin=req.headers.get('origin'),cors={'Access-Control-Allow-Origin':site||'','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
 if(req.method==='OPTIONS')return origin===site?new Response(null,{status:204,headers:cors}):j({error:'Origin denied'},403);
 if(req.method!=='POST')return j({error:'Method not allowed'},405,cors);
 const webhook=new URL(req.url).searchParams.get('webhook')==='1';
 if(!webhook&&(!site||origin!==site))return j({error:'Origin denied'},403);
 const headers=webhook?{}:cors;
 try{
  if(!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||!env.SUPABASE_ANON_KEY||!env.RAZORPAY_KEY_ID?.startsWith('rzp_test_')||!env.RAZORPAY_KEY_SECRET) return j({error:'Razorpay test payment is not configured'},503,headers);
  const raw=await req.text();if(raw.length>65536)return j({error:'Payload too large'},413,headers);
  const db=async(path,{method='GET',body,prefer}={})=>{const r=await fetch(env.SUPABASE_URL+'/rest/v1/'+path,{method,headers:{apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:'Bearer '+env.SUPABASE_SERVICE_ROLE_KEY,'Content-Type':'application/json',...(prefer?{Prefer:prefer}:{})},body:body?JSON.stringify(body):undefined});const text=await r.text();let d;try{d=JSON.parse(text)}catch{d=null}if(!r.ok)throw Error('Database operation failed');return d;};
  const razor=async(path,body)=>{const r=await fetch('https://api.razorpay.com/v1/'+path,{method:body?'POST':'GET',headers:{Authorization:'Basic '+btoa(env.RAZORPAY_KEY_ID+':'+env.RAZORPAY_KEY_SECRET),'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});if(!r.ok)throw Error('Payment provider request failed');return r.json();};
  const markPaid=async(booking,order,payment)=>{if(!validateCaptured(payment,order,booking))throw Error('Payment is not captured or its amount does not match');return db('rpc/carmitra_mark_paid',{method:'POST',body:{p_booking:booking.id,p_order:order.order_id,p_payment:payment.id}});};
  if(webhook){if(!env.RAZORPAY_WEBHOOK_SECRET)return j({error:'Webhook is not configured'},503);const sig=req.headers.get('x-razorpay-signature');if(!same(sig,await hmac(env.RAZORPAY_WEBHOOK_SECRET,raw)))return j({error:'Invalid webhook signature'},401);const event=JSON.parse(raw);if(event.event!=='payment.captured')return j({received:true});const payment=event.payload?.payment?.entity;if(!payment?.order_id)return j({error:'Missing payment'},400);const orders=await db('carmitra_payment_orders?order_id=eq.'+encodeURIComponent(payment.order_id));if(!orders.length)return j({error:'Unknown order'},404);const order=orders[0],bookings=await db('carmitra_bookings?id=eq.'+order.booking_id);if(!bookings.length)return j({error:'Unknown booking'},404);const livePayment=await razor('payments/'+encodeURIComponent(payment.id));await markPaid(bookings[0],order,livePayment);return j({received:true});}
  const token=req.headers.get('authorization');if(!token?.startsWith('Bearer '))return j({error:'Sign in required'},401,headers);
  const auth=await fetch(env.SUPABASE_URL+'/auth/v1/user',{headers:{Authorization:token,apikey:env.SUPABASE_ANON_KEY}});if(!auth.ok)return j({error:'Session expired. Please sign in again'},401,headers);const user=await auth.json();
  const body=JSON.parse(raw);if(!/^[a-f0-9-]{36}$/i.test(body.booking_id||''))return j({error:'Invalid booking'},400,headers);
  const bookings=await db('carmitra_bookings?id=eq.'+body.booking_id+'&user_id=eq.'+user.id);const booking=bookings[0];if(!booking||booking.payment_method!=='razorpay')return j({error:'Booking not found'},404,headers);
  const existing=await db('carmitra_payment_orders?booking_id=eq.'+booking.id);
  if(body.action==='order'){
   if(booking.payment_status==='paid')return j({error:'Booking already paid'},409,headers);
   if(booking.status!=='awaiting_payment'||Date.parse(booking.expires_at)<=Date.now())return j({error:'Reservation expired. Please book a new slot'},409,headers);
   let order=existing[0];if(!order){const created=await razor('orders',{amount:booking.total_paise,currency:'INR',receipt:booking.id,notes:{booking_id:booking.id}});await db('carmitra_payment_orders?on_conflict=booking_id',{method:'POST',prefer:'resolution=ignore-duplicates',body:{booking_id:booking.id,order_id:created.id,amount_paise:booking.total_paise}});order=(await db('carmitra_payment_orders?booking_id=eq.'+booking.id))[0];}
   return j({order_id:order.order_id,amount:order.amount_paise,key_id:env.RAZORPAY_KEY_ID,currency:'INR',mode:'test'},200,headers);
  }
  if(body.action==='verify'){
   const order=existing[0];if(!order||order.order_id!==body.razorpay_order_id||!/^pay_[A-Za-z0-9]+$/.test(body.razorpay_payment_id||''))return j({error:'Payment order mismatch'},400,headers);
   if(!same(body.razorpay_signature,await hmac(env.RAZORPAY_KEY_SECRET,order.order_id+'|'+body.razorpay_payment_id)))return j({error:'Invalid payment signature'},401,headers);
   const payment=await razor('payments/'+body.razorpay_payment_id);await markPaid(booking,order,payment);return j({verified:true},200,headers);
  }
  return j({error:'Unknown payment action'},400,headers);
 }catch(e){console.error('CarMitra payment operation failed:',e.message);return j({error:'Payment could not be confirmed. Check My bookings before retrying. Contact support if your payment was captured.'},409,headers);}
}
if(typeof Deno!=='undefined')Deno.serve(req=>handler(req,Object.fromEntries(['SITE_ORIGIN','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_ANON_KEY','RAZORPAY_KEY_ID','RAZORPAY_KEY_SECRET','RAZORPAY_WEBHOOK_SECRET'].map(k=>[k,Deno.env.get(k)]))));
