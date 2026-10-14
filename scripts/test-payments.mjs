import assert from 'node:assert/strict';
import {webcrypto,createHmac} from 'node:crypto';
import fs from 'node:fs';
if(!globalThis.crypto)Object.defineProperty(globalThis,"crypto",{value:webcrypto});
const source=fs.readFileSync('supabase/functions/carmitra-payments/index.js','utf8');
const {hmac,same,validateCaptured,handler}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
assert.equal(await hmac('secret','order_1|pay_1'),createHmac('sha256','secret').update('order_1|pay_1').digest('hex'));
assert(same('abc','abc'));assert(!same('abc','abd'));assert(!same(null,'abc'));
const b={total_paise:59900},o={order_id:'order_1'};
assert(validateCaptured({status:'captured',order_id:'order_1',amount:59900,currency:'INR'},o,b));
for(const override of [{status:'authorized'},{amount:1},{order_id:'order_other'},{currency:'USD'}])assert(!validateCaptured({status:'captured',order_id:'order_1',amount:59900,currency:'INR',...override},o,b));
assert.equal((await handler(new Request('https://x.test',{method:'GET'}),{})).status,405);
assert.equal((await handler(new Request('https://x.test',{method:'POST',headers:{origin:'https://evil.test'}}),{SITE_ORIGIN:'https://carmitra-jaipur.templateapp67.chatgpt.site'})).status,403);
const site='https://carmitra-jaipur.templateapp67.chatgpt.site';
assert.equal((await handler(new Request('https://x.test',{method:'POST',headers:{origin:site},body:'{}'}),{SITE_ORIGIN:site})).status,503);
const env={SITE_ORIGIN:site,SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-server-key',SUPABASE_ANON_KEY:'test-public-key',RAZORPAY_KEY_ID:'rzp_test_123',RAZORPAY_KEY_SECRET:'test'};
assert.equal((await handler(new Request('https://x.test',{method:'POST',headers:{origin:site},body:'{}'}),env)).status,401);
assert.equal((await handler(new Request('https://x.test?webhook=1',{method:'POST',body:'{}'}),{...env,RAZORPAY_WEBHOOK_SECRET:'test'})).status,401);
console.log('PASS: HMAC, amount/currency/order/capture validation, method, origin, missing configuration, customer auth and signed webhook gates.');
const originalFetch=globalThis.fetch;
let marked=0,foreign=false,tampered=false;
const bookingId='11111111-1111-1111-1111-111111111111';
globalThis.fetch=async(url,options={})=>{
 if(url.endsWith('/auth/v1/user'))return new Response(JSON.stringify({id:'customer-one'}));
 if(url.includes('/carmitra_bookings?')){assert(url.includes('user_id=eq.customer-one'));return new Response(JSON.stringify(foreign?[]:[{id:bookingId,user_id:'customer-one',payment_method:'razorpay',total_paise:59900}]));}
 if(url.includes('/carmitra_payment_orders?'))return new Response(JSON.stringify([{booking_id:bookingId,order_id:'order_one',amount_paise:59900}]));
 if(url.includes('/payments/pay_one'))return new Response(JSON.stringify({id:'pay_one',order_id:'order_one',amount:tampered?1:59900,currency:'INR',status:'captured'}));
 if(url.includes('/rpc/carmitra_mark_paid')){marked++;assert.deepEqual(JSON.parse(options.body),{p_booking:bookingId,p_order:'order_one',p_payment:'pay_one'});return new Response('true');}
 throw Error('Unexpected request '+url);
};
const signedBody={action:'verify',booking_id:bookingId,razorpay_order_id:'order_one',razorpay_payment_id:'pay_one',razorpay_signature:await hmac('test','order_one|pay_one')};
const request=()=>new Request('https://function.test',{method:'POST',headers:{origin:site,authorization:'Bearer test-user-token'},body:JSON.stringify(signedBody)});
assert.equal((await handler(request(),env)).status,200);assert.equal(marked,1);
foreign=true;assert.equal((await handler(request(),env)).status,404);assert.equal(marked,1);foreign=false;
tampered=true;assert.equal((await handler(request(),env)).status,409);assert.equal(marked,1);
globalThis.fetch=originalFetch;
console.log('PASS: captured-payment flow, cross-account rejection and tampered amount never marking booking paid.');
