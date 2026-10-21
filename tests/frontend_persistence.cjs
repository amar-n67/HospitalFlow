const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'../wwwroot');
const app=fs.readFileSync(path.join(root,'js/core/app.js'),'utf8');
const index=fs.readFileSync(path.join(root,'index.html'),'utf8');
const assets=[...index.matchAll(/(?:src|href)="(\/(?:js|css)\/[^"#]+)"/g)].map(m=>m[1].split('?')[0]);
assert.equal(new Set(assets).size,16);
for(const asset of assets)assert.ok(fs.statSync(path.join(root,asset)).isFile(),asset);
for(const folder of ['core','features'])for(const file of fs.readdirSync(path.join(root,'js',folder))){
 const source=fs.readFileSync(path.join(root,'js',folder,file),'utf8');
 assert.doesNotMatch(source,/\b(?:localStorage|sessionStorage|indexedDB)\s*\./,file);
 assert.ok(assets.includes('/js/'+folder+'/'+file),'Unreferenced asset: '+file);
}
const functions=app.split('\n');
const load=functions.find(line=>line.startsWith('async function load()'));
const themeHandler=functions.find(line=>line.startsWith('let themeSave='));
async function check(){
 const previous={patients:[{id:'previous'}]};
 const ctx={state:previous,me:{id:'nurse',role:'Nurse',theme:'Default'},historyPatientId:'',calendarYear:2026,can:()=>true,fullAccess:()=>false,canClinical:()=>true,render:()=>{},api:async url=>{if(url==='/api/work/tasks')throw Error('Database unavailable');return url==='/api/state'?{patients:[{id:'new'}]}:[];}};
 vm.createContext(ctx);vm.runInContext(load,ctx);
 await assert.rejects(vm.runInContext('load()',ctx),/Database unavailable/);
 assert.equal(ctx.state,previous,'Failed reload must preserve the last complete snapshot');
 ctx.api=async url=>url==='/api/state'?{patients:[{id:'new'}]}:[];
 await vm.runInContext('load()',ctx);assert.equal(ctx.state.patients[0].id,'new');
 let handler,applied,toasted;
 ctx.document={addEventListener:(name,fn)=>{handler=fn;}};
 ctx.$=()=>({classList:{contains:()=>false}});
 ctx.applyTheme=theme=>{applied=theme;};ctx.toast=message=>{toasted=message;};
 ctx.api=async()=>{throw Error('Database unavailable');};
 vm.runInContext(themeHandler,ctx);handler({detail:'Dark'});await vm.runInContext('themeSave',ctx);
 assert.equal(ctx.me.theme,'Default');assert.equal(applied,'Default');assert.match(toasted,/not saved/);
 ctx.api=async(url,data)=>{assert.equal(url,'/api/account/theme');assert.equal(data.theme,'Dark');};
 handler({detail:'Dark'});await vm.runInContext('themeSave',ctx);assert.equal(ctx.me.theme,'Dark');
 console.log('PASS: organized assets resolve; no browser data store; failed workspace reload stays atomic; theme requires a successful database save.');
}
check().catch(error=>{console.error(error);process.exitCode=1;});

const versionBadge={textContent:'',hidden:true,setAttribute(key,value){this[key]=value;}};
const versionCtx={me:{version:'1.1.0',commit:'abcdef1234567890abcdef1234567890abcdef12',workingTree:'modified'},document:{querySelectorAll:()=>[versionBadge]}};vm.createContext(versionCtx);
vm.runInContext(functions.find(line=>line.startsWith('function updateVersionBadge(')),versionCtx);
vm.runInContext('updateVersionBadge()',versionCtx);
assert.equal(versionBadge.textContent,'Version 1.1.0');assert.equal(versionBadge.hidden,false);assert.equal(versionBadge['aria-label'],versionBadge.textContent);
console.log('PASS: version label displays only the compiled version supplied by the server.');

assert.match(index,/HospitalFlow<\/a><div class="app-build"/);
assert.match(index,/id="login-build" class="app-build login-build"/);
assert.doesNotMatch(index,/class="app-footer"/);
versionCtx.me={version:'2.0.0',commit:null,workingTree:'unknown'};vm.runInContext('updateVersionBadge()',versionCtx);assert.equal(versionBadge.textContent,'Version 2.0.0');assert.doesNotMatch(versionBadge.textContent,/Commit|Uncommitted/);
console.log('PASS: version-only labels directly below the application logos.');

versionCtx.document.hidden=false;versionCtx.api=async url=>{assert.equal(url,'/api/health');return {version:'1.0.2'};};
vm.runInContext(functions.find(line=>line.startsWith('async function refreshRunningVersion(')),versionCtx);
vm.runInContext('refreshRunningVersion()',versionCtx).then(()=>{assert.equal(versionBadge.textContent,'Version 1.0.2');console.log('PASS: version polling picks up a restarted build without reloading page content.');}).catch(error=>{console.error(error);process.exitCode=1;});
