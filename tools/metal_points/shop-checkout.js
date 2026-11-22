'use strict';
const assert=require('node:assert/strict');
const {validateRequest:validateURL}=require('./shop-intake');
const {selectMetal}=require('./outgoing');
const {approved}=require('./owner-approval');
const id=i=>String(i.assetid||i.id||'');
const numeric=v=>typeof v==='string'&&/^[1-9][0-9]{0,19}$/.test(v);
function validate(r){
 for(const [owner,url] of [[r.buyer,r.buyer_url],[r.seller,r.seller_url]])validateURL({code:r.code,asset:r.asset,owner,url});
 assert(/^[a-f0-9]{32}$/.test(r.listing)&&r.buyer!==r.seller);
 assert(Number.isInteger(r.price.keys)&&r.price.keys>=0&&r.price.keys<=999999);
 assert(Number.isInteger(r.price.metal_scrap)&&r.price.metal_scrap>=0&&r.price.metal_scrap<=8999991);
 assert(r.price.keys+r.price.metal_scrap>0);
}
function identities(items){
 assert(Array.isArray(items)&&items.length<=1000);
 const ids=items.map(i=>{assert(Number(i.appid)===440&&String(i.contextid)==='2'&&String(i.amount)==='1'&&numeric(id(i)));return id(i);});
 assert(new Set(ids).size===ids.length);return ids.sort();
}
function selectPayment(inventory,price,locked){
 const keys=inventory.filter(i=>i.market_hash_name==='Mann Co. Supply Crate Key'&&i.tradable&&!locked.has(id(i))).slice(0,price.keys);
 if(keys.length!==price.keys)return null;
 const metal=price.metal_scrap?selectMetal(inventory,price.metal_scrap*10,locked):[];
 if(!metal)return null;
 const items=keys.concat(metal);identities(items);return items;
}
function checkOffer(offer,row,payout){
 assert(offer.isOurOffer&&numeric(offer.id)&&offer.partner.getSteamID64()===(payout?row.seller:row.buyer));
 const key=payout?'payout_offer':'buy_offer';assert(!row[key]||row[key]===offer.id);
 assert(!offer.message||offer.message===(payout?'PAYOUT ':'BUY ')+row.code);
 assert.deepEqual(identities(offer.itemsToGive),payout?identities(row.payments):[row.asset]);
 assert.deepEqual(identities(offer.itemsToReceive),payout?[]:identities(row.selected));
}
function receipt(offer,row,payout,status,received,given){
 checkOffer(offer,row,payout);assert(status===3&&numeric(offer.tradeID));
 assert.deepEqual(identities(given),payout?identities(row.payments):[row.asset]);
 assert.deepEqual(identities(received),payout?[]:identities(row.selected));
 assert(!given.concat(received).some(i=>i.rollback_new_assetid));
 if(payout)return [];
 const mapped=received.map(i=>{assert(numeric(i.new_assetid)&&String(i.new_contextid)==='2');return {appid:440,contextid:'2',assetid:i.new_assetid,amount:1};});
 identities(mapped);return mapped;
}
function approval(row){
 return {code:row.code,steamid:row.seller,url:row.seller_url,kind:'shop',points:Math.min(90000,Math.max(row.price.keys?5760:0,row.price.metal_scrap*10)),label:`${row.price.keys}키 + ${Math.floor(row.price.metal_scrap/9)}정 ${row.price.metal_scrap%9}폐 판매대금`};
}
function create({state,save,api,manager,call,community,identitySecret,hasTradeHold,log}){
 state.purchases ||= {};const busy=new Set();
 function custody(row){
  const intake=state.shop?.[row.listing];
  assert(intake?.done&&intake.status==='published'&&intake.owner===row.seller&&intake.bot_asset===row.asset,'Purchase custody owner/listing/asset mismatch');
 }
 async function update(row,status,extra={}){
  await api({action:'purchase_update',listing:row.listing,code:row.code,status,...extra});row.status=status;save();
 }
 async function process(offer){
  if(!offer.isOurOffer)return false;
  const row=Object.values(state.purchases).find(r=>r.buy_offer===offer.id||r.payout_offer===offer.id||offer.message==='BUY '+r.code||offer.message==='PAYOUT '+r.code);
  if(!row)return false;if(busy.has(row.code))return true;busy.add(row.code);
  try{
   const payout=row.payout_offer===offer.id||offer.message==='PAYOUT '+row.code;
   custody(row);
   assert(payout?row.payout_started:row.buy_started,'Offer must have a durable send intent');
   if(payout)assert(approved(state,approval(row)),'Seller payout approval required');
   checkOffer(offer,row,payout);
   if(['failed','settled','review'].includes(row.status))return true;
   const key=payout?'payout_offer':'buy_offer';row[key]=offer.id;save();
   if(offer.state===9){await call(community,'acceptConfirmationForObject',identitySecret,offer.id);return true;}
   if(payout){if(row.status==='paid')await update(row,'settling',{payout_offer:offer.id});}
   else if(row.status==='queued')await update(row,'sent',{buy_offer:offer.id});
   if(offer.state===3){
    const [status,,received,given]=await call(offer,'getExchangeDetails');
    const payments=receipt(offer,row,payout,status,received,given);
    if(payout){await update(row,'settled',{payout_trade:offer.tradeID});}
    else if(['sent','held'].includes(row.status)){
     row.payments=payments;row.buy_trade=offer.tradeID;save();
     await update(row,'paid',{buy_trade:offer.tradeID});
    }
   }else if([4,5,6,7,8,10].includes(offer.state))await update(row,payout?'review':'failed');
   else if(!payout&&offer.state===11&&row.status!=='held')await update(row,'held');
   return true;
  }finally{busy.delete(row.code);}
 }
 function reserved(){
  const ids=new Set();for(const r of Object.values(state.purchases))if(!['failed','settled'].includes(r.status)){
   ids.add(r.asset);for(const i of r.payments||[])ids.add(id(i));
  }return ids;
 }
 function uncertain(){return Object.values(state.purchases).some(r=>['queued','sent','held'].includes(r.status));}
 function approvals(){return Object.values(state.purchases).filter(r=>r.status==='paid'&&r.payout_requested&&!r.payout_started&&!r.review).map(approval);}
 async function tick(){
  const {requests}=await api({action:'purchases'});assert(Array.isArray(requests));
  for(const r of requests){validate(r);custody(r);const old=state.purchases[r.code];if(old){
   assert(old.listing===r.listing&&old.asset===r.asset&&old.buyer===r.buyer&&old.seller===r.seller);assert.deepEqual(old.price,r.price);
   if(r.payout_requested===true&&!old.payout_requested&&!old.payout_started){old.payout_requested=true;old.seller_url=r.seller_url;save();}
  }}
  const pending=Object.values(state.purchases).filter(r=>!['failed','settled','review'].includes(r.status));
  if(!requests.length&&!pending.length)return;
  const cutoff=new Date(Math.min(Date.now(),...pending.map(r=>r.started))-86400000);
  const [sent]=await call(manager,'getOffers',3,cutoff);
  const locked=new Set();
  for(const o of sent)if([2,9,11].includes(o.state))for(const i of o.itemsToGive)locked.add(id(i));
  for(const r of Object.values(state.outgoing||{}))if(!r.done)for(const asset of r.assets||[])locked.add(asset);
  for(const r of Object.values(state.finance||{}))if(!r.done&&r.kind==='capital_out')for(const i of r.selected||[])locked.add(id(i));
  for(const r of requests){
   const old=state.purchases[r.code];
   if(old&&(old.status!=='queued'||old.buy_started||old.buy_offer))continue;
   // Never reconstruct financial state from the web queue after loss of the bot ledger.
   if(r.status!=='queued'||r.buy_offer)throw Error('Purchase ledger missing or inconsistent');
   const row=old||{...r,started:Date.now()};state.purchases[r.code]=row;save();
   // Resume preparation only when no durable send intent or historical offer exists.
   assert(!sent.some(o=>o.isOurOffer&&o.message==='BUY '+row.code),'Purchase history without send intent');
   custody(row);
   if(locked.has(row.asset)){await update(row,'failed');continue;}
   try{
    const [inventory]=await call(manager,'getUserInventoryContents',row.buyer,440,'2',true);
    const buyerLocked=new Set();
    for(const other of Object.values(state.purchases))if(other.buyer===row.buyer&&!['failed','settled'].includes(other.status))for(const i of other.selected||[])buyerLocked.add(id(i));
    const selected=selectPayment(inventory,row.price,buyerLocked);
    if(!selected){await update(row,'failed');continue;}
    const offer=manager.createOffer(row.buyer_url);offer.setMessage('BUY '+row.code);
    offer.addMyItem({appid:440,contextid:'2',assetid:row.asset,amount:1});offer.addTheirItems(selected);
    const [me,them]=await call(offer,'getUserDetails');
    if(hasTradeHold(offer,me,them)){await update(row,'failed');continue;}
    row.selected=selected.map(i=>({appid:440,contextid:'2',assetid:id(i),amount:1}));row.buy_started=true;save();locked.add(row.asset);
    try{await call(offer,'send');assert(numeric(offer.id));row.buy_offer=offer.id;save();}catch{log('Purchase send uncertain; no resend');}
   }catch{if(!row.buy_started)await update(row,'failed');else log('Purchase remains reserved');}
  }
  for(const row of Object.values(state.purchases)){
   if(['failed','settled','review'].includes(row.status))continue;
   try{
    for(const [key,prefix] of [['buy_offer','BUY '],['payout_offer','PAYOUT ']]){
     if(!row[key]){const matches=sent.filter(o=>o.isOurOffer&&o.message===prefix+row.code);assert(matches.length<=1);if(matches.length){row[key]=matches[0].id;save();}}
     if(row[key]){const [offer]=await call(manager,'getOffer',row[key]);await process(offer);}
    }
    if(row.status!=='paid'||row.payout_started||!row.payout_requested)continue;
    if(row.review){await update(row,'review');continue;}
    if(!approved(state,approval(row)))continue;
    const [inventory]=await call(manager,'getInventoryContents',440,'2',true);
    if(row.payments.some(i=>locked.has(id(i))))continue;
    if(!row.payments.every(i=>inventory.some(v=>id(v)===id(i)&&v.tradable))){
     // Replace missing settlement money only with verified operator capital, never user custody.
     const capital=new Set(Object.values(state.finance||{}).filter(r=>r.kind==='capital_in'&&r.done&&r.status==='completed').flatMap(r=>(r.received||[]).map(id)));
     const unavailable=new Set([...locked,...reserved()]);
     for(const r of Object.values(state.shop||{}))if(r.bot_asset&&r.status!=='failed')unavailable.add(r.bot_asset);
     const replacement=selectPayment(inventory.filter(i=>capital.has(id(i))),row.price,unavailable);
     if(!replacement)continue;
     row.funding ||= [];row.funding.push({time:Date.now(),original:row.payments,replacement:replacement.map(i=>({appid:440,contextid:'2',assetid:id(i),amount:1})),reason:'operator capital covers unavailable seller payment'});
     row.payments=row.funding[row.funding.length-1].replacement;save();
    }
    const offer=manager.createOffer(row.seller_url);offer.setMessage('PAYOUT '+row.code);offer.addMyItems(row.payments);
    const [me,them]=await call(offer,'getUserDetails');if(hasTradeHold(offer,me,them))continue;
    row.payout_started=true;save();for(const i of row.payments)locked.add(id(i));
    try{await call(offer,'send');assert(numeric(offer.id));row.payout_offer=offer.id;save();}catch{log('Seller payout uncertain; no resend');}
   }catch{log('Purchase/settlement reconciliation pending');}
  }
 }
 return {process,tick,reserved,uncertain,approvals};
}
module.exports={create,validate,selectPayment,identities,checkOffer,receipt,approval};
