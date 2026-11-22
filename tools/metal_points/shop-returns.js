'use strict';
const assert=require('node:assert/strict');
const {validateRequest}=require('./shop-intake');
const {identities}=require('./shop-checkout');
const {approved}=require('./owner-approval');
const numeric=v=>typeof v==='string'&&/^[1-9][0-9]{0,19}$/.test(v);
function checkOffer(offer,row){
 assert(row.send_started&&offer.isOurOffer&&numeric(offer.id)&&offer.partner.getSteamID64()===row.owner);
 assert(!row.offer||row.offer===offer.id);assert(!offer.message||offer.message==='RETURN '+row.code);
 assert.deepEqual(identities(offer.itemsToGive),[row.asset]);assert.deepEqual(identities(offer.itemsToReceive),[]);
}
function verifyReceipt(offer,row,status,received,given){
 checkOffer(offer,row);assert(status===3&&numeric(offer.tradeID));
 assert.deepEqual(identities(received),[]);assert.deepEqual(identities(given),[row.asset]);
 assert(!given.some(i=>i.rollback_new_assetid));return offer.tradeID;
}
function approval(row){return {code:row.code,steamid:row.owner,url:row.url,kind:'return',points:row.points,label:'위탁 보관 열쇠 1개 반환'};}
function create({state,save,api,manager,call,community,identitySecret,hasTradeHold,log}){
 state.shopReturns ||= {};const busy=new Set();
 async function update(row,status,extra={}){
  await api({action:'return_update',code:row.code,listing:row.listing,status,...extra});row.status=status;save();
 }
 async function process(offer){
  if(!offer.isOurOffer)return false;
  const row=Object.values(state.shopReturns).find(r=>r.offer===offer.id||offer.message==='RETURN '+r.code);
  if(!row)return false;if(busy.has(row.code))return true;busy.add(row.code);
  try{
   checkOffer(offer,row);assert(approved(state,approval(row)));
   if(['returned','failed','review'].includes(row.status))return true;
   row.offer=offer.id;save();
   if(offer.state===9){await call(community,'acceptConfirmationForObject',identitySecret,offer.id);return true;}
   if(row.status==='queued')await update(row,'sent',{offer:offer.id});
   if(offer.state===3){const [status,,received,given]=await call(offer,'getExchangeDetails');await update(row,'returned',{trade:verifyReceipt(offer,row,status,received,given)});}
   else if([4,5,6,7,8,10].includes(offer.state))await update(row,'failed');
   else if(offer.state===11&&row.status!=='held')await update(row,'held');
   return true;
  }finally{busy.delete(row.code);}
 }
 function approvals(){return Object.values(state.shopReturns).filter(r=>r.status==='queued'&&!r.send_started&&!r.review&&Number.isInteger(r.points)).map(approval);}
 async function tick(){
  const {requests}=await api({action:'returns'});assert(Array.isArray(requests));
  for(const r of requests){
   validateRequest(r);assert(/^[a-f0-9]{32}$/.test(r.listing));
   const custody=state.shop?.[r.listing];
   assert(custody?.done&&custody.status==='published'&&custody.owner===r.owner&&custody.bot_asset===r.asset,'Return must match durable intake owner and asset');
   const old=state.shopReturns[r.code];
   if(old){assert(old.owner===r.owner&&old.asset===r.asset&&old.listing===r.listing);continue;}
   assert(r.status==='queued'&&!r.offer,'Missing return ledger');state.shopReturns[r.code]={...r,started:Date.now()};save();
  }
  const pending=Object.values(state.shopReturns).filter(r=>!['returned','failed','review'].includes(r.status));
  if(!pending.length)return;
  const [sent]=await call(manager,'getOffers',3,new Date(Math.min(...pending.map(r=>r.started))-86400000));
  const [inventory]=await call(manager,'getInventoryContents',440,'2',true);
  const locked=new Set();
  for(const o of sent)if([2,9,11].includes(o.state))for(const asset of identities(o.itemsToGive))locked.add(asset);
  for(const r of Object.values(state.outgoing||{}))if(!r.done)for(const asset of r.assets||[])locked.add(asset);
  for(const r of Object.values(state.purchases||{}))if(r.status!=='failed'){
   locked.add(r.asset);for(const asset of identities(r.payments||[]))locked.add(asset);
  }
  for(const r of Object.values(state.shopReturns))if(r.send_started&&!['failed','returned'].includes(r.status))locked.add(r.asset);
  for(const row of pending){
   try{
    if(!row.offer&&row.send_started){
     const matches=sent.filter(o=>o.isOurOffer&&o.message==='RETURN '+row.code&&o.partner.getSteamID64()===row.owner);assert(matches.length<=1);
     if(matches.length){row.offer=matches[0].id;save();}
    }
    if(row.offer){const [offer]=await call(manager,'getOffer',row.offer);await process(offer);continue;}
    if(row.send_started)continue;
    if(row.review){await update(row,'review');continue;}
    if(locked.has(row.asset))continue;
    const item=inventory.find(i=>String(i.assetid||i.id)===row.asset&&i.tradable);if(!item)continue;
    assert.deepEqual(identities([item]),[row.asset]);
    assert(typeof item.market_hash_name==='string'&&item.market_hash_name.length>0,'Item description required');
    const points=item.market_hash_name==='Mann Co. Supply Crate Key'?5760:10;
    if(row.points!==undefined)assert(row.points===points);else{row.points=points;save();}
    if(!approved(state,approval(row)))continue;
    const offer=manager.createOffer(row.url);offer.setMessage('RETURN '+row.code);offer.addMyItem({appid:440,contextid:'2',assetid:row.asset,amount:1});
    const [me,them]=await call(offer,'getUserDetails');if(hasTradeHold(offer,me,them))continue;
    row.send_started=true;save();locked.add(row.asset);
    try{await call(offer,'send');assert(numeric(offer.id));row.offer=offer.id;save();}catch{log('Return send uncertain; reservation retained, no resend');}
   }catch{log('Item return reconciliation pending');}
  }
 }
 return {tick,process,approvals};
}
module.exports={create,checkOffer,verifyReceipt,approval};
