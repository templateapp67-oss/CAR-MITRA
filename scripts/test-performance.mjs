import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
if(!process.execArgv.includes('--experimental-vm-modules')){const p=spawnSync(process.execPath,['--experimental-vm-modules',import.meta.filename],{stdio:'inherit'});process.exit(p.status??1);}
const names=JSON.parse(fs.readFileSync('src/performance-build.json')),html=fs.readFileSync('build/stage/index.html','utf8');
assert(!html.includes('fonts.googleapis.com'));assert(!html.includes('marketplace.js'));assert(!html.includes('preload" as="image'));assert(html.includes('srcset='));
for(const match of html.matchAll(/(?:src|href)="(\/(?:build|media)\/[^" ]+)"/g))assert(fs.existsSync('build/stage'+match[1]),match[1]);
for(const tag of html.match(/<img\b[^>]*>/g)||[]){assert(tag.includes('width=')&&tag.includes('height='));}
const body=fs.readFileSync('scripts/test-front.mjs','utf8').split('\nfor(const signedIn')[0].replace(/^import[^\n]+\n/,'');
const harness=Function('fs','vm',body+';return harness;')(fs,vm),h=harness(false);await new Promise(setImmediate);
// Fresh context with only initial chunks; the existing harness supplies reusable DOM/API mocks.
const ctx=h.ctx;delete ctx.window.CARMITRA_PUBLIC;const scripts=['config','backend-config','app','customer','public'];
const fresh=harness(false);await new Promise(setImmediate);
const c={...fresh.ctx,window:{addEventListener(){},scrollTo(){},open(){},IntersectionObserver:class{}},location:{search:'',hash:'',origin:'https://carmitra-jaipur.templateapp67.chatgpt.site'}};
// Remove previous global lexical environment by making a separate context with its own DOM nodes.
vm.createContext(c);const imports=[],modules=new Map();let observer;
c.IntersectionObserver=class{constructor(cb){this.cb=cb;observer=this;}observe(){}disconnect(){}};c.window.IntersectionObserver=c.IntersectionObserver;c.URL=URL;
async function loadModule(spec){imports.push(spec);if(!modules.has(spec)){const m=new vm.SourceTextModule(fs.readFileSync('build/stage'+spec,'utf8'),{context:c,importModuleDynamically:loadModule});modules.set(spec,m);await m.link(()=>{throw Error('Unexpected dependency')});await m.evaluate();}return modules.get(spec);}
// Get a clean client through initial scripts, and count only this startup's requests.
fresh.requests.length=0;
vm.runInContext(fs.readFileSync('build/stage'+names.boot,'utf8'),c,{importModuleDynamically:loadModule});
for(let i=0;i<8;i++)await new Promise(setImmediate);
assert.equal(imports.length,0,'Home loaded portal or media chunks eagerly');
const reviewRequests=fresh.requests.filter(r=>r.url.includes('carmitra_review_feed'));assert.equal(reviewRequests.length,1,'Duplicate Home reviews fetch');
assert(!fresh.requests.some(r=>r.url.includes('carmitra_videos')),'Videos fetched above fold');
vm.runInContext("render('services',false)",c);for(let i=0;i<4;i++)await new Promise(setImmediate);assert.equal(imports.length,0,'Services loaded dashboard chunks');
vm.runInContext("render('book',false)",c);for(let i=0;i<8;i++)await new Promise(setImmediate);assert(imports.includes(names['booking-ux']));assert(!fresh.nodes.main.innerHTML.includes('DEMO MODE'));assert(fresh.nodes['#booking-content'].innerHTML.includes('Set up your booking'));
vm.runInContext("render('partner',false)",c);for(let i=0;i<15;i++)await new Promise(setImmediate);
assert(imports.includes(names.marketplace));assert(imports.includes(names['partner-agreement']));assert(fresh.nodes.main.innerHTML.includes('Partner'));
assert(fresh.nodes.main.innerHTML.includes('English Version'));
console.log('PASS: compiled initial chunks, on-demand portal imports, one shared review request, deferred video fetch and partner agreement flow.');
console.log('PASS: hashed asset references, responsive image markup and self-hosted font.');

vm.runInContext("render('channel',false)",c);for(let i=0;i<15;i++)await new Promise(setImmediate);
const channelImages=fresh.nodes.main.innerHTML.match(/<img\b[^>]*>/g)||[];
const modelImages=channelImages.filter(tag=>tag.includes('programme detail card'));
assert.equal(modelImages.length,3);
const modelSources=[];
for(const tag of channelImages){
 const src=tag.match(/src="([^"]+)"/)?.[1];assert(src&&fs.existsSync('build/stage/client'+src),'Missing published channel image: '+src);
 for(const candidate of (tag.match(/srcset="([^"]+)"/)?.[1]||'').split(',').filter(Boolean))assert(fs.existsSync('build/stage/client'+candidate.trim().split(' ')[0]));
 if(modelImages.includes(tag)){assert(tag.includes('srcset=')&&tag.includes('loading="lazy"')&&tag.includes('width=')&&tag.includes('height='));modelSources.push(src);}
}
assert.equal(new Set(modelSources).size,3);
console.log('PASS: all rendered Channel Partner images and responsive candidates exist in the production artifact; model images are unique.');

const vehicleChunk=fs.readFileSync("build/stage"+names["booking-ux"],"utf8");const vehicleImages=[...vehicleChunk.matchAll(/\/media\/vehicle-[^ "'`<>]+?\.webp/g)].map(m=>m[0]);const mediaCatalog=JSON.parse(fs.readFileSync("src/vehicle-media.json"));const imageCount=Object.values(mediaCatalog).reduce((n,items)=>n+Object.keys(items).length,0);assert.equal(new Set(vehicleImages).size,imageCount);for(const url of vehicleImages)assert(fs.existsSync("build/stage/client"+url),"Unpublished vehicle image "+url);console.log(`PASS: ${Object.keys(mediaCatalog.makes).length} brand logos and ${Object.keys(mediaCatalog.models).length} model photos are included in the lazy booking chunk and published artifact.`);

vm.runInContext("location.search='?page=reviews';render('reviews',false)",c);for(let i=0;i<15;i++)await new Promise(setImmediate);assert(imports.includes(names.reviews),'Reviews module did not lazy load');assert(fresh.nodes.main.innerHTML.includes('reviews-experience'),'Reviews did not open after portal navigation');console.log('PASS: Reviews lazy module opens after a portal visit.');
