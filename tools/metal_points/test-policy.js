'use strict';
const assert = require('node:assert/strict');
const {metalValue, deposit, receipt, withdrawal, withdrawalReceipt, hasTradeHold} = require('./deposit-policy');
const metal = (name, id) => ({appid:440, contextid:'2', assetid:String(id), amount:'1', market_hash_name:name});
const items = [metal('Scrap Metal',1), metal('Reclaimed Metal',2), metal('Refined Metal',3)];
assert.equal(metalValue(items),130);
const offer = {id:'100', tradeID:'200', isOurOffer:false, message:'포인트', itemsToGive:[], itemsToReceive:items, partner:{getSteamID64:()=> '76561198038759714'}};
assert.equal(receipt(offer,3,items,[]).points,130);
for (const message of ['',undefined,'POINTS','donation','WITHDRAW invalid']) {
  assert.equal(deposit({...offer,message}).points,130);
  assert.equal(receipt({...offer,message},3,items,[]).points,130);
}
for (const patch of [{isOurOffer:true},{itemsToGive:items},{id:'../x'}, {itemsToReceive:[]}, {itemsToReceive:[metal('Mann Co. Supply Crate Key',4)]}]) {
  assert.throws(()=>deposit({...offer,...patch}));
}
for (const status of [0,1,2,4,5,6,7,8,9,10,11]) assert.throws(()=>receipt(offer,status,items,[]));
assert.throws(()=>receipt(offer,3,[items[0]],[]));
assert.throws(()=>receipt(offer,3,items,items));
assert.throws(()=>metalValue([items[0],items[0]]));
for (const patch of [{appid:730},{contextid:'6'},{amount:'2'},{assetid:'bad'}]) assert.throws(()=>metalValue([{...items[0],...patch}]));
console.log('Deposit policy: rates, no message required, outgoing prohibition, escrow, asset validation PASS');
const out={...offer,message:'WITHDRAW '+ 'a'.repeat(32),itemsToReceive:[],itemsToGive:items};
assert.equal(withdrawal(out).points,130);
assert.equal(withdrawalReceipt(out,3,[],items).points,130);
for(const patch of [{message:'WITHDRAW ../test'},{itemsToReceive:items},{itemsToGive:[]},{isOurOffer:true}]) assert.throws(()=>withdrawal({...out,...patch}));
assert.throws(()=>withdrawalReceipt(out,10,[],items));
assert.throws(()=>withdrawalReceipt(out,3,[],[items[0]]));
console.log('Withdrawal identity, direction, complete exchange validation PASS');
assert.equal(hasTradeHold(offer,{escrowDays:15},{escrowDays:0}),false);
assert.equal(hasTradeHold(offer,{escrowDays:0},{escrowDays:15}),true);
assert.equal(hasTradeHold(offer,{escrowDays:0},{}),true);
assert.equal(hasTradeHold(out,{escrowDays:15},{escrowDays:0}),true);
assert.equal(hasTradeHold(out,{escrowDays:0},{escrowDays:15}),false);
assert.equal(hasTradeHold(out,{}, {escrowDays:0}),true);
console.log('Escrow: check item-giving sides only; unknown duration blocks PASS');
const pending={...out,isOurOffer:true,message:''};
assert.throws(()=>withdrawal(pending,true));
assert.equal(withdrawal(pending,true,'a'.repeat(32)).points,130);
assert.throws(()=>withdrawal({...pending,isOurOffer:false},false,'a'.repeat(32)));
assert.throws(()=>withdrawal({...pending,message:'WITHDRAW '+'b'.repeat(32)},true,'a'.repeat(32)));
assert.equal(withdrawalReceipt(pending,3,[],items,true,'a'.repeat(32)).points,130);
console.log('Empty message: only durable bound outgoing identity permitted; mismatch and incoming blocked PASS');
