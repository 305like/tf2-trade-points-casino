'use strict';
const assert=require('node:assert/strict');
const {create,validate,selectPayment,receipt,approval}=require('./shop-checkout');
const {approved,createApproval,OWNER}=require('./owner-approval');
const item=(assetid,name='Scrap Metal')=>({appid:440,contextid:'2',assetid,amount:1,tradable:true,market_hash_name:name});
const request={code:'b'.repeat(32),listing:'a'.repeat(32),buyer:'76561198038759714',buyer_url:'https://steamcommunity.com/tradeoffer/new/?partner=78493986&token=Abc_123-',seller:'76561199077147589',seller_url:'https://steamcommunity.com/tradeoffer/new/?partner=1116881861&token=Abc_123-',asset:'500',price:{keys:0,metal_scrap:1},status:'queued',buy_offer:'',payout_offer:''};
validate(request);assert.throws(()=>validate({...request,seller:request.buyer}));
assert.equal(selectPayment([item('1','Refined Metal')],request.price,new Set()),null);
assert.equal(selectPayment([item('1')],request.price,new Set(['1'])),null);
assert.equal(selectPayment([item('1')],request.price,new Set()).length,1);
assert.equal(selectPayment([item('1')],{keys:1,metal_scrap:0},new Set()),null);
const base={...request,selected:[item('10')],buy_offer:'100'};
const buy={id:'100',isOurOffer:true,state:3,tradeID:'200',message:'BUY '+request.code,partner:{getSteamID64:()=>request.buyer},itemsToGive:[item('500')],itemsToReceive:[item('10')]};
const received=[{...item('10'),new_assetid:'20',new_contextid:'2'}];
assert.equal(receipt(buy,base,false,3,received,[item('500')])[0].assetid,'20');
for(const status of [2,4,11])assert.throws(()=>receipt(buy,base,false,status,received,[item('500')]));
assert.throws(()=>receipt({...buy,itemsToGive:[item('999')]},base,false,3,received,[item('999')]));
assert.throws(()=>receipt(buy,base,false,3,[{...received[0],rollback_new_assetid:'99'}],[item('500')]));
assert.equal(approved({},approval({...request,price:{keys:1,metal_scrap:0}})),false);
assert.equal(approved({},approval({...request,price:{keys:0,metal_scrap:576}})),false);
async function scenario({cancel=false,uncertain=false,resume=false,insufficient=false,wrongOwner=false,payoutMode="normal"}={}){
 const state={offers:{},outgoing:{},shop:{[request.listing]:{done:true,status:'published',owner:wrongOwner?request.buyer:request.seller,bot_asset:request.asset}}};
 if(payoutMode==='funded')state.finance={capital:{kind:'capital_in',done:true,status:'completed',received:[item('21')]}};
 if(resume)state.purchases={[request.code]:{...request,started:Date.now()}};
 const offers={};let next=100,sends=0;const updates=[];let claimed=false,payoutAvailable=payoutMode==="normal";
 const manager={createOffer(){const o={itemsToGive:[],itemsToReceive:[],isOurOffer:true,setMessage(m){this.message=m;},addMyItem(i){this.itemsToGive.push(i);},addMyItems(i){this.itemsToGive.push(...i);},addTheirItems(i){this.itemsToReceive.push(...i);}};return o;}};
 const api=async b=>{if(b.action==='purchases')return {requests:[{...request,payout_requested:claimed}]};updates.push(b);return {ok:true};};
 const call=async(o,m,...args)=>{
  if(m==='getOffers'){assert.equal(args[0],3);return [Object.values(offers),[]];}
  if(m==='getUserInventoryContents')return [insufficient?[]:[item('10')]];
  if(m==='getInventoryContents')return [payoutAvailable?[item('20')]:['replacement','funded'].includes(payoutMode)?[item('21')]:payoutMode==='untradable'?[{...item('20'),tradable:false}]:payoutMode==='locked'?[item('20')]:[]];
  if(m==='getUserDetails')return [{escrowDays:0},{escrowDays:0}];
  if(m==='send'){
   sends++;o.id=String(next++);o.state=2;o.partner={getSteamID64:()=>o.message.startsWith('BUY')?request.buyer:request.seller};offers[o.id]=o;
   if(uncertain&&sends===1)throw Error('response lost');return [];
  }
  if(m==='getOffer')return [offers[args[0]]];
  if(m==='getExchangeDetails')return [3,null,o.message.startsWith('BUY')?received:[],o.itemsToGive];
  throw Error(m);
 };
 let shop=create({state,save(){},api,manager,call,community:{},hasTradeHold:()=>false,log(){}});
 if(wrongOwner){await assert.rejects(shop.tick(),/custody/);assert.equal(sends,0);return;}
 if(insufficient){await shop.tick();await shop.tick();assert.equal(sends,0);assert.equal(state.purchases[request.code].status,'failed');assert(!shop.uncertain());assert(!shop.reserved().has('500'));return;}
 await shop.tick();await shop.tick();assert.equal(sends,1);assert(shop.uncertain());
 offers['100'].state=cancel?7:3;offers['100'].tradeID='200';
 await shop.tick();
 if(cancel){assert.equal(state.purchases[request.code].status,'failed');assert.equal(sends,1);return;}
 assert(shop.reserved().has('20'));assert.equal(sends,1);assert(!shop.uncertain());
 await shop.tick();assert.equal(sends,1,'no payout before seller claim');
 claimed=true;
 if(payoutMode==='locked')state.outgoing.blocked={done:false,assets:['20']};
 if(!['normal','funded'].includes(payoutMode)){
  await shop.tick();await shop.tick();assert.equal(sends,1);assert.equal(state.purchases[request.code].status,'paid');
  assert(!state.purchases[request.code].payout_started);assert(shop.reserved().has('20'));
  payoutAvailable=true;delete state.outgoing.blocked;
 }
 await shop.tick();assert.equal(sends,2);
 if(payoutMode==='funded'){assert.equal(state.purchases[request.code].payments[0].assetid,'21');assert.equal(state.purchases[request.code].funding[0].original[0].assetid,'20');}
 // Recreate handler against durable state, then finish seller payout without resending.
 shop=create({state,save(){},api,manager,call,community:{},hasTradeHold:()=>false,log(){}});
 await shop.tick();assert.equal(sends,2);
 offers['101'].state=3;offers['101'].tradeID='201';await shop.tick();await shop.tick();
 assert.equal(state.purchases[request.code].status,'settled');assert.equal(sends,2);assert.equal(updates.filter(b=>b.status==='settled').length,1);
 assert(!shop.reserved().has('20'));
}
(async()=>{
 for(const payoutMode of ['missing','replacement','untradable','locked'])await scenario({payoutMode});
 await scenario({payoutMode:'funded'});await scenario();await scenario({cancel:true});await scenario({uncertain:true});await scenario({resume:true});await scenario({insufficient:true});await scenario({wrongOwner:true});
 const high={...request,price:{keys:1,metal_scrap:0}};const state={purchases:{[high.code]:high},outgoing:{}};let clock=1000;
 const gate=createApproval({state,save(){},send:async()=>({server_timestamp:new Date(clock)}),api:async()=>{throw Error('must not refund points');},online:()=>true,now:()=>clock});
 await gate.tick([approval(high)]);clock++;
 await gate.reply({message:'아니오',steamid_friend:{getSteamID64:()=>OWNER},chat_entry_type:1,server_timestamp:new Date(clock)});
 await gate.tick([approval(high)]);assert(high.review);assert(!approved(state,approval(high)));
 console.log('PASS missing/replacement/untradable/locked seller payment stays paid and resumes with original assets; exact payment, receipt guards, full purchase/payout, cancellation, restart recovery, ambiguous send, owner-denied settlement custody');
})().catch(e=>{console.error(e);process.exitCode=1;});
