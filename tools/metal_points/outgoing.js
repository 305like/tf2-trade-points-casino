'use strict';
const assert=require('node:assert/strict');
const {metalValue}=require('./deposit-policy');

function validateRequest(row) {
  assert(/^[a-f0-9]{32}$/.test(row.code));
  assert(/^7656119[0-9]{10}$/.test(row.steamid));
  assert(Number.isInteger(row.points)&&row.points>=10&&row.points<=90000&&row.points%10===0);
  const account=(BigInt(row.steamid)-76561197960265728n).toString();
  assert(new RegExp('^https://steamcommunity\\.com/tradeoffer/new/\\?partner='+account+'&token=[A-Za-z0-9_-]{8}$').test(row.url));
}
function selectMetal(inventory,points,locked) {
  const result=[];
  for(const name of ['Refined Metal','Reclaimed Metal','Scrap Metal']) {
    for(const item of inventory) {
      if(item.market_hash_name!==name||!item.tradable||locked.has(String(item.assetid||item.id))) continue;
      const value=metalValue([item]);
      if(value>points) continue;
      result.push(item); points-=value;
      if(!points) {assert(result.length<=1000); return result;}
    }
  }
  return null;
}

// Persist intent before send: an ambiguous Steam response must never trigger a second send.
async function dispatch({requests,sent,inventory,state,save,manager,call,processOffer,hasTradeHold,log,canApprove}) {
  state.outgoing ||= {};
  const locked=new Set();
  for(const offer of sent) if([2,9,11].includes(offer.state))
    for(const item of offer.itemsToGive) locked.add(String(item.assetid||item.id));
  for(const row of Object.values(state.outgoing)) if(!row.done)
    for(const id of row.assets||[]) locked.add(id);
  for(const request of requests) {
    validateRequest(request);
    let row=state.outgoing[request.code];
    if(row) {
      assert(row.steamid===request.steamid&&row.points===request.points);
      if(row.done) continue;
      const matches=sent.filter(o=>o.message==='WITHDRAW '+request.code&&o.isOurOffer&&o.partner.getSteamID64()===row.steamid);
      assert(matches.length<=1,'duplicate outgoing offers require review');
      if(matches.length) {
        row.offer=matches[0].id; save(); await processOffer(matches[0]);
      }
      // No match is not proof of failure: history can lag or be unavailable.
      continue;
    }
    if(!canApprove?.(request)) continue;
    const items=selectMetal(inventory,request.points,locked);
    if(!items) {log('Outgoing withdrawal waiting for exact metal inventory'); continue;}
    const offer=manager.createOffer(request.url);
    offer.setMessage('WITHDRAW '+request.code); offer.addMyItems(items);
    const [me,them]=await call(offer,'getUserDetails');
    if(hasTradeHold(offer,me,them)) {log('Outgoing withdrawal waiting for Steam trade restrictions'); continue;}
    row={steamid:request.steamid,points:request.points,assets:items.map(i=>String(i.assetid||i.id)),started:Date.now()};
    state.outgoing[request.code]=row;
    for(const id of row.assets) locked.add(id);
    save();
    try {
      await call(offer,'send');
      assert(/^[1-9][0-9]{0,19}$/.test(offer.id));
      row.offer=offer.id; save();
      // addMyItems strips descriptions; only the fetched offer can pass metal validation.
      const [hydrated]=await call(manager,'getOffer',offer.id);
      await processOffer(hydrated);
    } catch {
      // Retain both points and asset reservations until Steam history proves an outcome.
      log('Outgoing send outcome uncertain; retained reservation, no automatic resend');
    }
  }
}
module.exports={validateRequest,selectMetal,dispatch};
