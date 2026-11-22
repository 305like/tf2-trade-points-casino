'use strict';
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const assert=require('node:assert/strict');
function load(file){
 // A missing operating ledger is not a new installation: never spend unclassified custody.
 const state=JSON.parse(fs.readFileSync(file,'utf8'));
 assert(state&&state.offers&&typeof state.offers==='object'&&!Array.isArray(state.offers),'Invalid operating ledger');
 return state;
}
function daily(dir,state,now=new Date()){
 const day=new Date(now.getTime()+9*3600000).toISOString().slice(0,10);
 const folder=path.join(dir,'ledger-backups');fs.mkdirSync(folder,{recursive:true,mode:0o700});
 const file=path.join(folder,day+'.txt');
 if(fs.existsSync(file)){
  const saved=JSON.parse(fs.readFileSync(file,'utf8'));
  assert(saved.format===1&&typeof saved.data==='string'&&saved.sha256===crypto.createHash('sha256').update(saved.data).digest('hex'),'Daily backup checksum mismatch');
  return file;
 }
 const data=JSON.stringify(state);
 const body=JSON.stringify({format:1,created_at:now.toISOString(),sha256:crypto.createHash('sha256').update(data).digest('hex'),data});
 const temp=file+'.'+crypto.randomBytes(8).toString('hex')+'.tmp';
 try{
  const fd=fs.openSync(temp,'wx',0o600);
  try{fs.writeFileSync(fd,body);fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
  // Publish only a complete snapshot, without replacing an earlier snapshot of this day.
  try{fs.linkSync(temp,file);}catch(e){if(e.code!=='EEXIST')throw e;}
 }finally{if(fs.existsSync(temp))fs.unlinkSync(temp);}
 return file;
}
module.exports={load,daily};
