'use strict';
const assert=require('node:assert/strict');
const {validateRequest}=require('./shop-intake');
const {identities,selectPayment}=require('./shop-checkout');
const {value,priceValue,ownerPayment,summary}=require('./treasury');
const {OWNER}=require('./owner-approval');
const asset=i=>String(i.assetid||i.id);
function validate(r){
 validateRequest({...r,asset:'1'});
 assert(['topup','capital_in','capital_out'].includes(r.kind));
 if(r.kind!=='topup')assert.equal(r.owner,OWNER);
 const n=priceValue(r.price);assert(n>0&&n<=90000);
}
function check(offer,row){
 assert(offer.isOurOffer&&offer.partner.getSteamID64()===row.owner);
 assert(/^[1-9][0-9]{0,19}$/.test(offer.id)&&(!row.offer||row.offer===offer.id));
 assert(!offer.message||offer.message==='FUNDS '+row.code);
 const out=row.kind==='capital_out';
 assert.deepEqual(identities(out?offer.itemsToGive:offer.itemsToReceive),identities(row.selected));
 assert.equal((out?offer.itemsToReceive:offer.itemsToGive).length,0);
}
function receipt(offer,row,status,received,given){
 check(offer,row);assert(status===3&&/^[1-9][0-9]{0,19}$/.test(offer.tradeID));
 const out=row.kind==='capital_out',items=out?given:received;
 assert.equal((out?received:given).length,0);
 assert.deepEqual(identities(items),identities(row.selected));
 assert(!items.some(i=>i.rollback_new_assetid));
 if(!out)for(const i of items)assert(/^[1-9][0-9]{0,19}$/.test(i.new_assetid)&&String(i.new_contextid)==='2');
 const mapped=items.map(i=>({appid:440,contextid:'2',assetid:out?asset(i):i.new_assetid,amount:1,market_hash_name:row.selected.find(s=>asset(s)===asset(i)).market_hash_name}));
 identities(mapped);return mapped;
}
function create({state,save,api,pointApi,manager,call,community,identitySecret,hasTradeHold,log}){
 state.finance ||= {};let ticking=false;const busy=new Set();
 async function update(row,status,extra={}){
  await api({action:'finance_update',code:row.code,status,...extra});row.status=status;save();
 }
 async function process(offer){
  const row=offer.isOurOffer&&Object.values(state.finance).find(r=>r.offer===offer.id||offer.message==='FUNDS '+r.code);
  if(!row)return false;if(busy.has(row.code))return true;busy.add(row.code);
  try{
   assert(row.send_started);check(offer,row);row.offer=offer.id;save();if(row.done)return true;
   if(offer.state===9){await call(community,'acceptConfirmationForObject',identitySecret,offer.id);return true;}
   if(offer.state===3){
    const [status,,received,given]=await call(offer,'getExchangeDetails');
    row.received=receipt(offer,row,status,received,given);row.trade=offer.tradeID;save();
    if(row.kind==='topup'){
     const result=await pointApi({offer:offer.id,trade:offer.tradeID,steamid:row.owner,points:priceValue(row.price)});
     if(result.status!=='credited')return true;
    }
    await update(row,'completed',{offer:offer.id,trade:offer.tradeID});row.done=true;row.completed_at=Date.now();save();
   }else if([1,4,5,6,7,8,10].includes(offer.state)){
    await update(row,'failed',{offer:offer.id});row.done=true;save();
   }else await update(row,offer.state===11?'held':'sent',{offer:offer.id});
   return true;
  }finally{busy.delete(row.code);}
 }
 async function tick(){
  if(ticking)return;ticking=true;
  try{
   const data=await api({action:'finance_queue'});assert(Array.isArray(data.requests)&&Array.isArray(data.ledger));
   const ledger=new Map(data.ledger.map(r=>{validate(r);return [r.code,r];}));assert.equal(ledger.size,data.ledger.length);
   for(const row of Object.values(state.finance)){
    const remote=ledger.get(row.code);assert(remote&&remote.owner===row.owner&&remote.kind===row.kind,'Finance ledger identity missing');
    assert.deepEqual(remote.price,row.price);
    if(remote.offer&&row.offer)assert.equal(remote.offer,row.offer);
    if(remote.trade)assert.equal(remote.trade,row.trade);
   }
   for(const row of data.ledger)if(row.offer||row.trade||row.status==='completed')assert(state.finance[row.code],'Finance ledger lost; restore required');
   const pending=Object.values(state.finance).filter(r=>!r.done);
   const [sent]=await call(manager,'getOffers',3,new Date(Math.min(Date.now(),...pending.map(r=>r.started))-86400000));
   const [inventory]=await call(manager,'getInventoryContents',440,'2',false);
   for(const request of data.requests){
    validate(request);if(request.kind==='topup'&&!state.finance[request.code]){await api({action:'finance_update',code:request.code,status:'failed'});continue;}let row=state.finance[request.code];
    if(row){assert(row.owner===request.owner&&row.kind===request.kind);assert.deepEqual(row.price,request.price);continue;}
    assert(!sent.some(o=>o.isOurOffer&&o.message==='FUNDS '+request.code),'Missing finance intent');
    row={...request,started:Date.now()};state.finance[row.code]=row;save();
   }
   for(const row of Object.values(state.finance)){
    if(row.done)continue;
    try{
     if(!row.offer&&row.send_started){const matches=sent.filter(o=>o.isOurOffer&&o.message==='FUNDS '+row.code);assert(matches.length<=1);if(matches.length){row.offer=matches[0].id;save();}}
     if(row.offer){const [offer]=await call(manager,'getOffer',row.offer);await process(offer);continue;}
     if(row.send_started)continue;
     if(row.kind==='topup'){await update(row,'failed');row.done=true;save();continue;}
     // Owner withdrawals wait for all inbound custody and purchases to settle before evaluating liabilities.
     let selected;
     if(row.kind==='capital_out'){
      if(Object.values(state.offers||{}).some(r=>!r.done)||Object.values(state.finance).some(r=>r.code!==row.code&&!r.done))continue;
      if(Object.values(state.shop||{}).some(r=>!r.done)||Object.values(state.purchases||{}).some(r=>['queued','sent','held'].includes(r.status)))continue;
      const fresh=await api({action:'finance_queue'});
      if(fresh.wallet_pending)continue;
      selected=ownerPayment(row,state,inventory,fresh.wallet,sent);
     }else{
      const [items]=await call(manager,'getUserInventoryContents',row.owner,440,'2',true);
      const locked=new Set();for(const r of Object.values(state.finance))if(!r.done&&r.owner===row.owner&&r.send_started)for(const i of r.selected||[])locked.add(asset(i));
      selected=selectPayment(items,row.price,locked);
     }
     if(!selected){await update(row,'waiting');continue;}
     assert.equal(value(selected),priceValue(row.price));
     const offer=manager.createOffer(row.url);offer.setMessage('FUNDS '+row.code);
     if(row.kind==='capital_out')offer.addMyItems(selected);else offer.addTheirItems(selected);
     const [me,them]=await call(offer,'getUserDetails');if(hasTradeHold(offer,me,them))continue;
     row.selected=selected.map(i=>({appid:440,contextid:'2',assetid:asset(i),amount:1,market_hash_name:i.market_hash_name}));row.send_started=true;save();
     try{await call(offer,'send');assert(/^[1-9][0-9]{0,19}$/.test(offer.id));row.offer=offer.id;save();await update(row,'sent',{offer:offer.id});}catch{log('Finance send uncertain; retained intent, no resend');}
    }catch{log('Finance reconciliation pending');}
   }
   const report=summary(state,inventory,data.wallet,sent);
   // Publish denominations only, never account tokens or inventory identifiers.
   const counts={};for(const i of report.freeItems)counts[i.market_hash_name]=(counts[i.market_hash_name]||0)+1;
   delete report.freeItems;
   await api({action:'finance_snapshot',report,counts});
  }finally{ticking=false;}
 }
 function reserved(){return new Set(Object.values(state.finance).filter(r=>!r.done&&r.kind==='capital_out').flatMap(r=>(r.selected||[]).map(asset)));}
 return {process,tick,reserved};
}
module.exports={create,validate,check,receipt};
