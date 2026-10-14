import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const code=fs.readFileSync('scripts/test-front.mjs','utf8').split('\nfor(const signedIn')[0].replace(/^import[^\n]+\n/,'').replace('focus(){},scrollIntoView()','insertAdjacentHTML(pos,html){this.innerHTML+=html;},focus(){},scrollIntoView()');const harness=Function('fs','vm',code+';return harness;')(fs,vm);const h=harness(false);await new Promise(setImmediate);
h.ctx.FormData=class{constructor(f){this.fields=f.fields||{};}*[Symbol.iterator](){yield*Object.entries(this.fields);}};
h.data.carmitra_services=[{id:22,name:'Bucket Wash - Basic',category:0,price_paise:24900,duration_minutes:30,is_package:true,inclusions:['Exterior wash','Tyre polish'],active:true},{id:23,name:'Pressure Wash - Premium',category:0,price_paise:49900,duration_minutes:60,is_package:true,inclusions:['Exterior pressure wash','Tyre polish'],active:true},{id:24,name:'360 Deep Cleaning',category:3,price_paise:99900,duration_minutes:120,is_package:true,inclusions:['Interior vacuum','Roof cleaning','Seat cleaning'],active:true}];h.data.carmitra_vehicle_multipliers=[{vehicle_type:'sedan',basis_points:10000}];
h.ctx.crypto={randomUUID:()=> 'request-one'};const originalFetch=h.ctx.fetch;let bookedBody;
h.ctx.fetch=async(url,opts={})=>{const body=opts.body?JSON.parse(opts.body):{};if(url.includes('/carmitra_vehicles')&&opts.method==='POST'){h.data.carmitra_vehicles=[{id:'saved-vehicle',...body}];return new Response(JSON.stringify(h.data.carmitra_vehicles));}if(url.includes('/carmitra_addresses')&&opts.method==='POST'){h.data.carmitra_addresses=[{id:'saved-address',...body}];return new Response(JSON.stringify(h.data.carmitra_addresses));}if(url.includes('/rpc/carmitra_available_slots'))return new Response(JSON.stringify([{id:'slot-one',starts_at:'2026-10-20T04:00:00Z',remaining:1}]));if(url.includes('/rpc/carmitra_quote_with_coupon'))return new Response(JSON.stringify({total_paise:24900,subtotal_paise:24900,discount_paise:0,duration_minutes:30}));if(url.includes('/rpc/carmitra_create_booking_discounted')){bookedBody=body;return new Response(JSON.stringify({id:'confirmed-booking',starts_at:'2026-10-20T04:00:00Z',total_paise:24900,payment_method:'cash'}));}return originalFetch(url,opts);};
h.ctx.window.CARMITRA_VEHICLE_MEDIA=JSON.parse(fs.readFileSync('src/vehicle-media.json'));
vm.runInContext(fs.readFileSync('src/site/booking-ux.js','utf8'),h.ctx);vm.runInContext("render('book',false)",h.ctx);await new Promise(setImmediate);assert(h.nodes['#booking-content'].innerHTML.includes('Set up your booking'));
const uxClick=h.handlers.click.find(f=>f.toString().includes('data-setup-next'));
const button=(attr,dataset={})=>({dataset,disabled:false,isConnected:true,textContent:'Continue',hasAttribute:a=>a===attr});
async function click(attr,dataset={}){const b=button(attr,dataset);await uxClick({target:{closest:s=>s==='button'?b:null}});await new Promise(setImmediate);}
const uxChange=h.handlers.change.find(f=>f.toString().includes('setup-city'));
h.ctx.window.CARMITRA.areas=['Vaishali Nagar','C-Scheme','Civil Lines','Bani Park','Malviya Nagar','Mansarovar','Raja Park','Jagatpura','Shyam Nagar','Tonk Road'];
await h.ctx.window.CARMITRA_CLIENT.refreshBooking();assert(h.nodes['#booking-content'].innerHTML.includes('Jaipur, Rajasthan'));assert.equal((h.nodes['#booking-content'].innerHTML.match(/data-setup-area=/g)||[]).length,10);
await click('data-setup-next');assert(!h.nodes['#booking-content'].innerHTML.includes('vehicle-picker-dialog'),'Area gate bypassed');
const areaSearch=h.handlers.input.find(f=>f.toString().includes('setup-area-search'));areaSearch({target:{id:'setup-area-search',value:'civil'}});assert(h.nodes['#setup-area-grid'].innerHTML.includes('Civil Lines'));assert(!h.nodes['#setup-area-grid'].innerHTML.includes('Mansarovar'));
await click('',{setupArea:'Vaishali Nagar'});
await click('data-setup-next');assert(h.nodes['#booking-content'].innerHTML.includes('Search car brand'));
assert.equal((h.nodes['#booking-content'].innerHTML.match(/class="vehicle-make-card"/g)||[]).length,28);
assert(h.nodes['#booking-content'].innerHTML.includes('vehicle-picker-dialog'));assert(h.nodes['#booking-content'].innerHTML.includes('Add new vehicle'));
const popup=h.ctx.document.querySelector('#vehicle-picker-dialog');let closed=0,opened=0;popup.close=()=>closed++;popup.showModal=()=>opened++;
await click('data-close-vehicle-picker');await click('data-open-vehicle-picker');assert.equal(closed,1);assert.equal(opened,1);
const makeSearch=h.handlers.input.find(f=>f.toString().includes('make-search'));makeSearch({target:{id:'make-search',value:'Swift'}});assert(h.nodes['#make-grid'].innerHTML.includes('Maruti Suzuki'));assert(!h.nodes['#make-grid'].innerHTML.includes('Honda'));
for(const brand of Object.keys(h.ctx.window.CARMITRA_VEHICLE_MEDIA.makes)){await click('',{make:brand});const html=h.nodes['#booking-content'].innerHTML;const cards=html.match(/<button class="vehicle-model-card"[\s\S]*?<\/button>/g)||[];assert(cards.length,brand+' has no models');for(const card of cards){assert(card.includes('<img '),brand+' model has no image');const src=card.match(/src="([^"]+)"/)[1];assert(fs.existsSync('src/site'+src),src);}await click('data-setup-back');}
await click('',{make:'Honda'});assert(h.nodes['#booking-content'].innerHTML.includes('Select Honda Model'));
await click('',{model:'City',vehicleType:'sedan'});await click('data-vehicle-ready');assert(h.nodes['#booking-content'].innerHTML.includes('Choose a Package'));assert(h.nodes['#booking-content'].innerHTML.includes('₹249'));assert(h.nodes['#booking-content'].innerHTML.includes('₹499'));
await uxChange({target:{name:'choose-package',value:'22'}});assert.deepEqual([...h.ctx.window.CARMITRA_CLIENT.state.services],[22]);await click('data-add-to-cart');assert(h.nodes.main.innerHTML.includes('Welcome to CarMitra'));
await h.handlers.click.find(f=>f.toString().includes('[data-auth-mode]'))({target:{closest:s=>s==='[data-auth-mode]'?{dataset:{authMode:'phone'}}:null}});
h.nodes['#auth-phone']={value:'9876543210'};
const authHandler=h.handlers.submit.find(f=>f.toString().includes("form.id==='auth-form'"));const authEvent={target:{id:'auth-form',querySelector:()=>button('')},preventDefault(){}};
await authHandler(authEvent);assert(h.nodes['#auth-message'].innerHTML.includes('No SMS was sent'));
h.nodes['#auth-otp']={value:'000000'};await authHandler(authEvent);assert(h.nodes['#auth-message'].innerHTML.includes('Incorrect demo OTP'));
h.nodes['#auth-otp'].value='123456';await authHandler(authEvent);assert(h.nodes['#auth-message'].innerHTML.includes('Demo OTP verified'));assert.equal(h.ctx.window.CARMITRA_CLIENT.session,null);assert(!h.requests.some(r=>r.url.includes('/auth/v1/otp')||r.url.includes('/auth/v1/verify')));
h.nodes['#auth-email']={value:'fixture@example.invalid'};h.nodes['#auth-password']={value:'fixture-password'};
await h.handlers.submit.find(f=>f.toString().includes("form.id==='auth-form'"))({target:{id:'auth-form',querySelector:()=>button('')},preventDefault(){}});await new Promise(setImmediate);assert(h.nodes['#booking-content'].innerHTML.includes('Save your vehicle'));
await h.handlers.submit.find(f=>f.toString().includes('custom-model-form'))({target:{id:'booking-vehicle-details',fields:{registration:'RJ14AB1234',fuel:'Petrol'},querySelector:()=>button('')},preventDefault(){}});
assert.equal(h.ctx.window.CARMITRA_CLIENT.state.vehicle,'saved-vehicle');assert(h.nodes['#booking-content'].innerHTML.includes('value="Vaishali Nagar"'));assert(h.nodes['#booking-content'].innerHTML.includes('How to Reach Instructions'),h.nodes['#booking-content'].innerHTML);
const address={id:'address-form',fields:{label:'Home',address_type:'home',line1:'House 21, Jaipur street',floor:'2',landmark:'Near main park',instructions:'Call at gate',selected_address:'Vaishali Nagar, Jaipur',locality:'Vaishali Nagar',pin_code:'302021',contact_phone:'9876543210',latitude:'',longitude:''},querySelector:()=>button('')};
await h.handlers.submit.find(f=>f.toString().includes("form.id==='auth-form'"))({target:address,preventDefault(){}});assert.equal(h.ctx.window.CARMITRA_CLIENT.state.address,'saved-address');assert.equal(h.data.carmitra_addresses[0].instructions,'Call at gate');
const customerClick=h.handlers.click.find(f=>f.toString().includes("e.target.closest('#confirm-booking')"));
async function customerButton(selector){const b=button('');await customerClick({target:{closest:s=>s===selector||s==='button'?b:null},preventDefault(){},stopImmediatePropagation(){}});}
await customerButton('[data-step-next]');assert.equal(h.ctx.window.CARMITRA_CLIENT.state.step,4);
await click('',{bookingDate:'2026-10-20'});assert(h.nodes['#slot-list'].innerHTML.includes('available'));
await h.handlers.change.find(f=>f.toString().includes("e.target.name==='choose-slot'"))({target:{name:'choose-slot',value:'slot-one'}});await customerButton('[data-step-next]');assert(h.nodes['#booking-content'].innerHTML.includes('Review & pay'));
h.nodes['#booking-consent']={checked:true};await customerButton('#confirm-booking');assert.equal(bookedBody.p_vehicle,'saved-vehicle');assert.equal(bookedBody.p_address,'saved-address');assert.equal(bookedBody.p_slot,'slot-one');assert.equal(bookedBody.p_payment,'cash');assert(h.nodes.main.innerHTML.includes('Booking confirmed.'));
console.log('PASS: guest Jaipur → make/model → package/cart → email login → vehicle persistence → full address persistence → slot → server quote → booking confirmation.');

console.log("PASS: vehicle modal close/reopen and search by car model name.");

console.log("PASS: fixed Jaipur city, ten popular areas, area search, required selection and address locality prefill.");
