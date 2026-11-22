'use strict';
const assert=require('node:assert/strict');
function verify(state,rows){
 assert(Array.isArray(rows),'Web ledger unavailable');
 const seen=new Set();
 for(const r of rows){
  assert(typeof r.code==='string'&&!seen.has(r.code),'Duplicate listing ledger');seen.add(r.code);
  const local=state.shop?.[r.code];
  if(local){
   assert(local.owner===r.owner&&local.asset===r.asset,'Intake ledger ownership mismatch');
   if(r.bot_asset&&local.bot_asset)assert(r.bot_asset===local.bot_asset,'Custody asset mismatch');
   if(local.status==='published')assert(r.status==='published'&&r.bot_asset===local.bot_asset,'Published custody missing on web');
  }
  if(r.status==='published')assert(local?.bot_asset===r.bot_asset&&local.bot_asset,'Published custody missing locally');
  for(const order of r.orders||[]){
   assert(order.listing===r.code&&order.seller===r.owner&&order.asset===r.bot_asset,'Web purchase ownership mismatch');
   const p=state.purchases?.[order.code];
   if(p){
    for(const key of ['listing','seller','buyer','asset'])assert(p[key]===order[key],'Purchase ledger mismatch');
    assert.deepEqual(p.price,order.price,'Purchase price changed');
    for(const key of ['buy_offer','payout_offer','buy_trade','payout_trade'])if(p[key]&&order[key])assert(p[key]===order[key],'Purchase receipt mismatch');
    if(p.status==='settled'&&order.status==='settled')for(const key of ['buy_offer','buy_trade','payout_offer','payout_trade'])assert(p[key]&&p[key]===order[key],'Completed purchase receipt missing or different');
   }else assert(order.status==='queued'&&!order.buy_offer,'Purchase ledger missing locally');
  }
  for(const ret of r.returns||[]){
   assert(ret.listing===r.code&&ret.owner===r.owner&&ret.asset===r.bot_asset,'Web return ownership mismatch');
   const p=state.shopReturns?.[ret.code];
   if(p){for(const key of ['listing','owner','asset'])assert(p[key]===ret[key],'Return ledger mismatch');if(p.offer&&ret.offer)assert(p.offer===ret.offer,'Return offer mismatch');}
   else assert(ret.status==='queued'&&!ret.offer,'Return ledger missing locally');
  }
 }
 for(const row of Object.values(state.shop||{}))assert(seen.has(row.code),'Local intake absent from web ledger');
}
module.exports={verify};
