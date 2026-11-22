'use strict';
const assert=require('node:assert/strict');
const {create,validate,receipt}=require('./shop-finance');
const {OWNER}=require('./owner-approval');
const item=(id,name='Refined Metal')=>({appid:440,contextid:'2',assetid:id,amount:1,tradable:true,market_hash_name:name});
const base={code:'a'.repeat(32),owner:OWNER,url:'https://steamcommunity.com/tradeoffer/new/?partner=78493986&token=Abc_123-',kind:'capital_in',price:{keys:0,metal_scrap:9},status:'queued'};
validate(base);assert.throws(()=>validate({...base,owner:'76561199077147589'}));
assert.throws(()=>validate({...base,price:{keys:0,metal_scrap:-1}}));
async function scenario(kind,uncertain=false){
 const state={offers:{}};let sends=0,credits=0;const offers={},updates=[];
 const request={...base,kind};
 const manager={createOffer(){return {isOurOffer:true,itemsToGive:[],itemsToReceive:[],partner:{getSteamID64:()=>OWNER},setMessage(m){this.message=m;},addMyItems(i){this.itemsToGive=i;},addTheirItems(i){this.itemsToReceive=i;}};}};
 const api=async b=>{if(b.action==='finance_queue')return {requests:[request],ledger:[request],wallet:{points:0,withdrawals:0}};updates.push(b);return {ok:true};};
 const call=async(o,m,...args)=>{
  if(m==='getOffers')return [Object.values(offers)];
  if(m==='getInventoryContents'||m==='getUserInventoryContents')return [[item('1'),item('2')]];
  if(m==='getUserDetails')return [{escrowDays:0},{escrowDays:0}];
  if(m==='send'){sends++;o.id='100';o.state=2;offers[o.id]=o;if(uncertain)throw Error('response lost');return [];}
  if(m==='getOffer')return [offers[args[0]]];
  if(m==='getExchangeDetails')return [3,null,o.itemsToReceive.map(i=>({...i,new_assetid:'200',new_contextid:'2'})),o.itemsToGive];
  throw Error(m);
 };
 const options={state,save(){},api,pointApi:async()=>{credits++;return {status:'credited'};},manager,call,community:{},identitySecret:'fixture',hasTradeHold:()=>false,log(){}};
 let module=create(options);await module.tick();
 if(kind==='topup'){
  assert.equal(sends,0);assert.equal(credits,0);assert(updates.some(b=>b.status==='failed'));
  state.finance[base.code]={...request,started:Date.now()};await module.tick();
  assert.equal(state.finance[base.code].status,'failed');assert.equal(sends,0);assert.equal(credits,0);return;
 }
 assert.equal(sends,1);
 module=create(options);await module.tick();assert.equal(sends,1);
 offers['100'].state=3;offers['100'].tradeID='300';await module.process(offers['100']);await module.process(offers['100']);
 assert.equal(state.finance[base.code].status,'completed');assert.equal(credits,kind==='topup'?1:0);
 assert(state.finance[base.code].done);assert.equal(updates.filter(b=>b.status==='completed').length,1);
 await module.tick();assert.equal(sends,1);
 const row=state.finance[base.code];
 assert.throws(()=>receipt(offers['100'],row,11,[],[]));
 assert.throws(()=>receipt({...offers['100'],partner:{getSteamID64:()=> '76561199077147589'}},row,3,[],[]));
}
(async()=>{for(const kind of ['topup','capital_in','capital_out'])for(const uncertain of [false,true])await scenario(kind,uncertain);console.log('PASS capital is not point credit, confirmed receipts only, owner restrictions, restart, ambiguous send and duplicate settlement');})().catch(e=>{console.error(e);process.exitCode=1;});
