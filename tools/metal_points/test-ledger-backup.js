'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {load,daily}=require('./ledger-backup');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bot-ledger-test-'));
try{
 const file=path.join(dir,'state.json');
 assert.throws(()=>load(file));
 fs.writeFileSync(file,'broken');assert.throws(()=>load(file));
 fs.writeFileSync(file,'{}');assert.throws(()=>load(file));
 const state={offers:{},shop:{test:{owner:'fixture',bot_asset:'123'}}};
 fs.writeFileSync(file,JSON.stringify(state));assert.deepEqual(load(file),state);
 const before=new Date('2026-10-30T14:59:59Z'),after=new Date('2026-10-30T15:00:00Z');
 const first=daily(dir,state,before);const original=fs.readFileSync(first,'utf8');
 state.shop.test.bot_asset='456';assert.equal(daily(dir,state,before),first);
 assert.equal(fs.readFileSync(first,'utf8'),original);
 const second=daily(dir,state,after);assert.notEqual(first,second);
 assert.equal(JSON.parse(JSON.parse(fs.readFileSync(second,'utf8')).data).shop.test.bot_asset,'456');
 fs.writeFileSync(second,'{}');assert.throws(()=>daily(dir,state,after));
 console.log('PASS missing/corrupt ledger blocks startup; daily KST immutable backup, checksum and midnight rollover');
}finally{fs.rmSync(dir,{recursive:true,force:true});}
