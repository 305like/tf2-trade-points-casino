'use strict';
const assert=require('node:assert/strict');
const {create,verifyReceipt,approval}=require('./shop-returns');
const {approved,createApproval,OWNER}=require('./owner-approval');
const request={code:'c'.repeat(32),listing:'a'.repeat(32),owner:'76561199077147589',asset:'500',url:'https://steamcommunity.com/tradeoffer/new/?partner=1116881861&token=Abc_123-',status:'queued',offer:''};
const item={appid:440,contextid:'2',assetid:'500',amount:1,tradable:true,market_hash_name:'Refined Metal'};
const offer={id:'600',tradeID:'700',isOurOffer:true,message:'RETURN '+request.code,partner:{getSteamID64:()=>request.owner},itemsToGive:[item],itemsToReceive:[]};
const row={...request,send_started:true};
assert.equal(verifyReceipt(offer,row,3,[],[item]),'700');
for(const status of [2,4,11])assert.throws(()=>verifyReceipt(offer,row,status,[],[item]));
assert.throws(()=>verifyReceipt(offer,{...row,send_started:false},3,[],[item]));
assert.throws(()=>verifyReceipt({...offer,partner:{getSteamID64:()=>OWNER}},row,3,[],[item]));
assert.throws(()=>verifyReceipt(offer,row,3,[],[{...item,assetid:'501'}]));
assert.throws(()=>verifyReceipt(offer,row,3,[],[{...item,rollback_new_assetid:'501'}]));
async function scenario({uncertain=false,cancel=false,key=false}={}){
 const state={shop:{[request.listing]:{done:true,status:'published',owner:request.owner,bot_asset:request.asset}}};let sends=0;const offers={};const updates=[];
 const manager={createOffer(){return {setMessage(m){this.message=m;},addMyItem(i){this.itemsToGive=[i];},itemsToReceive:[],isOurOffer:true,partner:offer.partner};}};
 const api=async b=>b.action==='returns'?{requests:[request]}:(updates.push(b),{ok:true});
 const call=async(o,m,...args)=>{
  if(m==='getOffers')return [Object.values(offers),[]];
  if(m==='getInventoryContents')return [[{...item,market_hash_name:key?'Mann Co. Supply Crate Key':'Refined Metal'}]];
  if(m==='getUserDetails')return [{escrowDays:0},{escrowDays:0}];
  if(m==='send'){sends++;o.id='600';o.state=2;offers['600']=o;if(uncertain)throw Error('response lost');return [];}
  if(m==='getOffer')return [offers[args[0]]];
  if(m==='getExchangeDetails')return [3,null,[],[item]];
  throw Error(m);
 };
 const args={state,save(){},api,manager,call,community:{},hasTradeHold:()=>false,log(){}};
 let bot=create(args);await bot.tick();await bot.tick();
 if(key){
  assert.equal(sends,0);assert.equal(bot.approvals().length,1);
  const a=approval(state.shopReturns[request.code]);assert(!approved(state,a));
  state.approvals={[a.code]:{steamid:a.steamid,points:a.points,decision:'yes'}};await bot.tick();
 }
 assert.equal(sends,1);bot=create(args);await bot.tick();assert.equal(sends,1);
 offers['600'].state=11;await bot.tick();assert.equal(state.shopReturns[request.code].status,'held');
 offers['600'].state=cancel?7:3;offers['600'].tradeID='700';await bot.tick();await bot.tick();
 assert.equal(state.shopReturns[request.code].status,cancel?'failed':'returned');assert.equal(sends,1);
 assert.equal(updates.filter(b=>b.status==='returned').length,cancel?0:1);
}
(async()=>{
 await scenario();await scenario({uncertain:true});await scenario({cancel:true});await scenario({key:true});
 const r={...request,points:5760};const state={shopReturns:{[r.code]:r}};let time=1000;
 const gate=createApproval({state,save(){},api:async()=>{throw Error('no points refund');},send:async()=>({server_timestamp:new Date(time)}),online:()=>true,now:()=>time});
 await gate.tick([approval(r)]);time++;
 await gate.reply({message:'아니오',steamid_friend:{getSteamID64:()=>OWNER},chat_entry_type:1,server_timestamp:new Date(time)});await gate.tick([approval(r)]);assert(r.review);
 console.log('PASS exact owner/item return, escrow, cancellation, complete receipt, restart, uncertain-send recovery, key approval and denial');
})().catch(e=>{console.error(e);process.exitCode=1;});
