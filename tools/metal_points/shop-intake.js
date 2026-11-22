'use strict';
const assert=require('node:assert/strict');
const id=v=>typeof v==='string'&&/^[1-9][0-9]{0,19}$/.test(v);
function validateRequest(r){
 assert(/^[a-f0-9]{32}$/.test(r.code)&&/^7656119[0-9]{10}$/.test(r.owner)&&id(r.asset));
 const account=(BigInt(r.owner)-76561197960265728n).toString();
 assert(new RegExp('^https://steamcommunity\\.com/tradeoffer/new/\\?partner='+account+'&token=[A-Za-z0-9_-]{8}$').test(r.url));
}
function validateOffer(offer,row){
 assert(offer.isOurOffer&&id(offer.id)&&offer.partner.getSteamID64()===row.owner);
 assert(offer.itemsToGive.length===0&&offer.itemsToReceive.length===1);
 const item=offer.itemsToReceive[0];
 assert(Number(item.appid)===440&&String(item.contextid)==='2'&&String(item.amount)==='1'&&String(item.assetid||item.id)===row.asset);
 assert(!row.offer||row.offer===offer.id);
 assert(!offer.message||offer.message==='SHOP '+row.code);
}
function verifyReceipt(offer,row,status,received,given){
 validateOffer(offer,row);assert(status===3&&given.length===0&&received.length===1&&id(offer.tradeID));
 const item=received[0];
 assert(Number(item.appid)===440&&String(item.contextid)==='2'&&String(item.amount)==='1'&&String(item.assetid)===row.asset);
 assert(id(item.new_assetid)&&String(item.new_contextid)==='2'&&!item.rollback_new_assetid);
 return {trade:offer.tradeID,bot_asset:item.new_assetid};
}
function create({state,save,api,manager,call,community,identitySecret,hasTradeHold,log}){
 state.shop ||= {};
 const processing=new Set();
 let ticking=false,polling=false;
 const nextAttempt=new Map();
 function find(offer){
  if(!offer.isOurOffer)return null;
  return Object.values(state.shop).find(r=>r.offer===offer.id||(!r.offer&&offer.message==='SHOP '+r.code))||null;
 }
 async function process(offer){
  const row=find(offer);if(!row)return false;
  if(processing.has(row.code))return true;
  processing.add(row.code);
  try {
  validateOffer(offer,row);row.offer=offer.id;save();
  if(row.done)return true;
  let outcome;
  if(offer.state===9){await call(community,'acceptConfirmationForObject',identitySecret,offer.id);return true;}
  if(offer.state===3){
   const [status,,received,given]=await call(offer,'getExchangeDetails');
   const receipt=verifyReceipt(offer,row,status,received,given);
   // Reserve custody before contacting the web service, including during outages.
   row.bot_asset=receipt.bot_asset;save();
   const [inventory]=await call(manager,'getInventoryContents',440,'2',false);
   assert(inventory.some(i=>String(i.assetid||i.id)===row.bot_asset&&Number(i.appid)===440&&String(i.contextid)==='2'&&String(i.amount)==='1'),'received asset absent');
   outcome={status:'published',...receipt};
  } else if([1,4,5,6,7,8,10].includes(offer.state))outcome={status:'failed'};
  else if(offer.state===11)outcome={status:'held'};
  else if(offer.state===2)outcome={status:'sent'};
  else return true;
  await api({action:'update',code:row.code,owner:row.owner,asset:row.asset,offer:row.offer,...outcome});
  if(['published','failed'].includes(outcome.status)){row.done=true;row.status=outcome.status;save();}
  return true;
  } finally {processing.delete(row.code);}
 }
 async function reconcile(queue){
  const {requests}=queue||await api({action:'queue'});assert(Array.isArray(requests));
  for(const r of requests)validateRequest(r);
  const pending=Object.values(state.shop).filter(r=>!r.done);
  if(!requests.length&&!pending.length)return;
  const start=Math.min(Date.now(),...pending.map(r=>r.started));
  const [sent]=await call(manager,'getOffers',3,new Date(start-86400000));
  for(const r of requests){
   let row=state.shop[r.code];
   if(row){assert(row.owner===r.owner&&row.asset===r.asset);continue;}
   const offer=manager.createOffer(r.url);offer.setMessage('SHOP '+r.code);
   offer.addTheirItem({appid:440,contextid:'2',assetid:r.asset,amount:1});
   const [me,them]=await call(offer,'getUserDetails');
   if(hasTradeHold(offer,me,them)){log('Shop intake waiting for Steam trade restrictions');continue;}
   row={code:r.code,owner:r.owner,asset:r.asset,started:Date.now()};state.shop[r.code]=row;save();
   try{
    await call(offer,'send');assert(id(offer.id));row.offer=offer.id;save();
   }catch{log('Shop intake send uncertain; retained intent, no automatic resend');}
  }
  for(const row of Object.values(state.shop)){
   if(row.done)continue;
   try{
    if(!row.offer){
     const matches=sent.filter(o=>o.isOurOffer&&o.message==='SHOP '+row.code&&o.partner.getSteamID64()===row.owner);
     assert(matches.length<=1,'duplicate intake offers');
     if(!matches.length)continue;
     row.offer=matches[0].id;save();
    }
    const [offer]=await call(manager,'getOffer',row.offer);await process(offer);
   }catch{log('Shop intake reconciliation pending');}
  }
 }
 async function tick(queue){
  if(ticking)return;ticking=true;
  try{await reconcile(queue);}finally{ticking=false;}
 }
 async function pollNew(){
  if(polling||ticking)return;polling=true;
  try{
   const {requests}=await api({action:'queue'});assert(Array.isArray(requests));
   for(const r of requests)validateRequest(r);
   for(const code of nextAttempt.keys())if(state.shop[code])nextAttempt.delete(code);
   const fresh=requests.filter(r=>!state.shop[r.code]&&(nextAttempt.get(r.code)||0)<=Date.now());
   if(!fresh.length)return;
   // Fast web polling must not repeatedly query Steam for restricted or failed requests.
   for(const r of fresh)nextAttempt.set(r.code,Date.now()+30000);
   await tick({requests:fresh});
  }finally{polling=false;}
 }
 function reserved(){return new Set(Object.values(state.shop).filter(r=>r.bot_asset&&r.status!=='failed').map(r=>r.bot_asset));}
 return {process,tick,pollNew,reserved,isBusy:()=>polling||ticking};
}
module.exports={create,validateRequest,validateOffer,verifyReceipt};
