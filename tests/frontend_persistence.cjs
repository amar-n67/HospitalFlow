const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'../HospitalFlow/wwwroot');
const app=fs.readFileSync(path.join(root,'js/core/app.js'),'utf8');
const index=fs.readFileSync(path.join(root,'index.html'),'utf8');
const assets=[...index.matchAll(/(?:src|href)="(\/(?:js|css)\/[^"?#]+)"/g)].map(m=>m[1]);
assert.equal(new Set(assets).size,15);
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
 const ctx={state:previous,me:{id:'nurse',role:'Nurse',theme:'Default'},historyPatientId:'',can:()=>true,fullAccess:()=>false,canClinical:()=>true,render:()=>{},api:async url=>{if(url==='/api/work/tasks')throw Error('Database unavailable');return url==='/api/state'?{patients:[{id:'new'}]}:[];}};
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
