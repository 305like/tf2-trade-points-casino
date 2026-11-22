'use strict';
const assert=require('node:assert/strict');
const {validateRequest,selectMetal,dispatch}=require('./outgoing');
const {withdrawal,withdrawalReceipt,hasTradeHold}=require('./deposit-policy');
const request={code:'a'.repeat(32),steamid:'76561199077147589',points:90,url:'https://steamcommunity.com/tradeoffer/new/?partner=1116881861&token=abcdefgh'};
const metal=(name,id)=>({appid:440,contextid:'2',assetid:String(id),amount:'1',market_hash_name:name,tradable:true});
const inventory=[metal('Refined Metal',1),metal('Reclaimed Metal',2),metal('Scrap Metal',3)];
validateRequest(request);
for(const change of [{points:91},{points:-10},{url:request.url.replace('1116881861','1116881862')},{url:request.url+'&x=1'},{code:'../bad'}]) assert.throws(()=>validateRequest({...request,...change}));
assert.deepEqual(selectMetal(inventory,100,new Set()).map(i=>i.assetid),['1','3']);
assert.equal(selectMetal(inventory,90,new Set(['1'])),null);
assert.equal(selectMetal(inventory,20,new Set()),null);
assert.equal(selectMetal([{...inventory[0],tradable:false}],90,new Set()),null);
async function main() {
  let sentCount=0,saves=0,processed=0,mode='ok';
  const state={};
  let hydrated;
  const offer={isOurOffer:true,state:9,itemsToReceive:[],partner:{getSteamID64:()=>request.steamid},
    setMessage(m){this.message=m;},addMyItems(items){this.itemsToGive=items.map(({appid,contextid,assetid,amount})=>({appid,contextid,assetid,amount}));}};
  const args={requests:[request],sent:[],inventory,state,canApprove:()=>true,save(){saves++;},manager:{createOffer(){return offer;}},
    async call(o,method){
      if(method==='getUserDetails') return [{escrowDays:mode==='hold'?15:0},{escrowDays:0}];
      if(method==='getOffer') {
        hydrated={...offer,itemsToGive:offer.itemsToGive.map(i=>({...i,market_hash_name:'Refined Metal'}))};
        return [hydrated];
      }
      assert.equal(method,'send'); assert(state.outgoing[request.code]); assert(saves>0); sentCount++;
      if(mode==='timeout') throw Error('network');
      o.id='100'; return ['pending'];
    },async processOffer(o){assert.equal(o.id,'100'); assert.equal(withdrawal(o,true).points,90); processed++;},hasTradeHold,log(){}};
  await dispatch({...args,inventory:[]});assert.equal(sentCount,0);assert(!state.outgoing[request.code]);
  await dispatch(args); assert.equal(sentCount,1); assert.equal(processed,1);
  await dispatch(args); assert.equal(sentCount,1);
  await dispatch({...args,sent:[hydrated]}); assert.equal(sentCount,1); assert.equal(processed,2);
  assert.throws(()=>withdrawal(offer,true));
  assert.equal(withdrawal(hydrated,true).points,90);
  assert.throws(()=>withdrawal(offer));
  assert.equal(withdrawalReceipt({...hydrated,tradeID:'200'},3,[],hydrated.itemsToGive,true).points,90);
  assert.throws(()=>withdrawalReceipt({...offer,tradeID:'200'},10,[],offer.itemsToGive,true));
  // Crash/timeout intent remains durable: retry/history absence never sends a duplicate.
  delete state.outgoing[request.code]; mode='timeout';
  await dispatch(args); const after=sentCount;
  const recovered=JSON.parse(JSON.stringify(state));
  await dispatch({...args,state:recovered}); assert.equal(sentCount,after);
  await dispatch({...args,state:recovered,sent:[hydrated]}); assert.equal(sentCount,after);
  delete state.outgoing[request.code]; mode='hold';
  await dispatch(args); assert.equal(sentCount,after); assert(!state.outgoing[request.code]);
  // Exact asset reservations prevent concurrent requests spending the same inventory.
  mode='ok';
  await dispatch({...args,requests:[request,{...request,code:'b'.repeat(32)}]});
  assert.equal(sentCount,after+1); assert(!state.outgoing['b'.repeat(32)]);
  console.log('Outgoing: URL ownership, exact metal, escrow, durable intent, recovery, no duplicate send/assets, complete-only settlement PASS');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
