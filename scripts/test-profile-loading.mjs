import {gunzipSync} from 'node:zlib';
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
if(!process.execArgv.includes('--experimental-vm-modules')){const p=spawnSync(process.execPath,['--experimental-vm-modules',import.meta.filename],{stdio:'inherit'});process.exit(p.status??1);}
const retained=JSON.parse(fs.readFileSync('src/retained-build-chunks.json'));
function chunk(spec){if(fs.existsSync('build/stage'+spec))return fs.readFileSync('build/stage'+spec,'utf8');const record=retained[spec];assert(record,'Missing previous deployment chunk '+spec);const bytes=Buffer.from(record[0],'base64');return (record[3]==='gzip'?gunzipSync(bytes):bytes).toString();}
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
async function loadModule(spec){imports.push(spec);if(!modules.has(spec)){const m=new vm.SourceTextModule(chunk(spec),{context:c,importModuleDynamically:loadModule});modules.set(spec,m);await m.link(()=>{throw Error('Unexpected dependency')});await m.evaluate();}return modules.get(spec);}
fresh.requests.length=0;
c.location.search='?page=profile';
c.localStorage={getItem:()=>JSON.stringify({access_token:'fixture-token',refresh_token:'fixture-refresh',expires_at:Math.floor(Date.now()/1000)+3600}),setItem(){},removeItem(){}};
vm.runInContext(chunk(process.env.OLD_PROFILE_BOOT||names.boot),c,{importModuleDynamically:loadModule});
for(let i=0;i<30;i++)await new Promise(setImmediate);
assert(!fresh.nodes.main.innerHTML.includes('could not load'),fresh.nodes.main.innerHTML);
assert(fresh.nodes.main.innerHTML.includes('My Profile'),fresh.nodes.main.innerHTML);
console.log('PASS: compiled signed-in profile opens on initial page load.');
