'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const source=fs.readFileSync(__dirname+'/deposit-bot.js','utf8');
const body=source.slice(source.indexOf('let reconciling=false;'),source.indexOf("manager.on('newOffer'"));
async function main() {
  const state={offers:{},outgoing:{request:{offer:'9450651373',started:Date.now(),done:false}}};
  const seen=[];
  const call=async(_,method,...args)=>{
    if(method==='getOffer') {assert.equal(args[0],'9450651373');return [{id:args[0]}];}
    if(method==='getOffers') {
      if(args[0]===3) assert(args[1] instanceof Date&&args[1].getTime()<state.outgoing.request.started);
      return [[],[]];
    }
    assert.equal(method,'getInventoryContents');throw Error('Inventory unavailable');
  };
  const fn=new Function('ownerChat','ready','state','call','manager','processOffer','failure','Manager','api','dispatch','save','hasTradeHold','log','shop','checkout','returns','ledgerBackup','dir','verifyLedger',body+';return reconcile;')(
    {tick:async()=>{}},true,state,call,{},async o=>seen.push(o.id),()=>{},{EOfferFilter:{ActiveOnly:1,All:3}},async()=>({requests:[{}]}),async()=>{throw Error('must not send');},()=>{},()=>{},()=>{},{tick:async()=>{},reserved:()=>new Set(),isBusy:()=>false},{tick:async()=>{},approvals:()=>[],uncertain:()=>false,reserved:()=>new Set()},{tick:async()=>{},approvals:()=>[]},{daily(){}},'fixture',async()=>{});
  await fn();await fn();
  assert.deepEqual(seen,['9450651373','9450651373']);
  console.log('Reconcile: persisted offer recovered without state.offers or inventory; historical cutoff explicit PASS');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
