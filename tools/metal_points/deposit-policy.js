'use strict';
const assert = require('node:assert/strict');
const rates = new Map([['Scrap Metal', 10], ['Reclaimed Metal', 30], ['Refined Metal', 90]]);
function metalValue(items) {
  assert(Array.isArray(items) && items.length > 0 && items.length <= 1000, 'metal count');
  const seen = new Set();
  let points = 0;
  for (const item of items) {
    assert(Number(item.appid) === 440 && String(item.contextid) === '2', 'TF2 inventory only');
    assert(rates.has(item.market_hash_name), 'metal only');
    assert(String(item.amount) === '1', 'unstacked metal only');
    const id = String(item.assetid || item.id || '');
    assert(/^[1-9][0-9]{0,19}$/.test(id) && !seen.has(id), 'asset identity');
    seen.add(id);
    points += rates.get(item.market_hash_name);
  }
  return points;
}
function deposit(offer) {
  assert(!offer.isOurOffer, 'received offers only');
  assert(offer.itemsToGive.length === 0, 'no outgoing items');
  const steamid = offer.partner.getSteamID64();
  assert(/^7656119[0-9]{10}$/.test(steamid), 'SteamID64');
  assert(/^[1-9][0-9]{0,19}$/.test(offer.id), 'offer id');
  return {offer: offer.id, steamid, points: metalValue(offer.itemsToReceive)};
}
function receipt(offer, status, received, given) {
  const row = deposit(offer);
  assert(status === 3, 'exchange must be Complete, not escrow');
  assert(Array.isArray(given) && given.length === 0, 'no outgoing exchange');
  assert(metalValue(received) === row.points, 'completed exchange differs from offer');
  assert(/^[1-9][0-9]{0,19}$/.test(offer.tradeID), 'trade id');
  return {...row, trade: offer.tradeID};
}
function withdrawal(offer, outgoing=false, boundCode=null) {
  assert(!!offer.isOurOffer === outgoing && offer.itemsToReceive.length === 0, 'withdrawal direction');
  // Steam may return an empty message for our pending-confirmation offers.
  const message=(offer.message||'').trim();
  if(boundCode!==null) assert(outgoing&&/^[a-f0-9]{32}$/.test(boundCode),'bound outgoing code');
  const match=/^WITHDRAW ([a-f0-9]{32})$/i.exec(message|| (boundCode?'WITHDRAW '+boundCode:''));
  assert(match,'withdrawal code');
  if(boundCode!==null) assert(match[1].toLowerCase()===boundCode,'bound code mismatch');
  const steamid=offer.partner.getSteamID64();
  assert(/^7656119[0-9]{10}$/.test(steamid) && /^[1-9][0-9]{0,19}$/.test(offer.id),'withdrawal identity');
  return {offer:offer.id,code:match[1].toLowerCase(),steamid,points:metalValue(offer.itemsToGive)};
}
function withdrawalReceipt(offer,status,received,given,outgoing=false,boundCode=null) {
  const row=withdrawal(offer,outgoing,boundCode);
  assert(status===3 && received.length===0 && metalValue(given)===row.points,'withdrawal exchange');
  assert(/^[1-9][0-9]{0,19}$/.test(offer.tradeID),'trade id');
  return {...row,trade:offer.tradeID};
}
function hasTradeHold(offer, me, them) {
  // Only the side giving items can cause escrow; unknown durations fail closed.
  return (offer.itemsToGive.length > 0 && me.escrowDays !== 0)
    || (offer.itemsToReceive.length > 0 && them.escrowDays !== 0);
}
module.exports = {metalValue, deposit, receipt, withdrawal, withdrawalReceipt, hasTradeHold};
