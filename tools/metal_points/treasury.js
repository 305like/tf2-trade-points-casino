'use strict';
const assert=require('node:assert/strict');
const {metalValue}=require('./deposit-policy');
const {selectPayment,identities}=require('./shop-checkout');
const {OWNER}=require('./owner-approval');
const KEY='Mann Co. Supply Crate Key';
function value(items){
 identities(items);
 return items.reduce((n,i)=>n+(i.market_hash_name===KEY?5760:metalValue([i])),0);
}
function priceValue(p){
 assert(Number.isSafeInteger(p.keys)&&p.keys>=0&&Number.isSafeInteger(p.metal_scrap)&&p.metal_scrap>=0);
 const n=p.keys*5760+p.metal_scrap*10;assert(Number.isSafeInteger(n));return n;
}
function reservations(state){
 const ids=new Set();
 for(const r of Object.values(state.shop||{}))if(r.bot_asset&&r.status!=='failed')ids.add(r.bot_asset);
 for(const r of Object.values(state.purchases||{}))if(!['failed','settled'].includes(r.status)){
  ids.add(r.asset);for(const i of r.payments||[])ids.add(String(i.assetid||i.id));
 }
 for(const r of Object.values(state.outgoing||{}))if(!r.done)for(const id of r.assets||[])ids.add(id);
 for(const r of Object.values(state.finance||{}))if(!r.done&&r.kind==='capital_out')for(const i of r.selected||[])ids.add(String(i.assetid||i.id));
 return ids;
}
function summary(state,inventory,wallet,sent=[]){
 assert(Number.isSafeInteger(wallet.points)&&wallet.points>=0&&Number.isSafeInteger(wallet.withdrawals)&&wallet.withdrawals>=0);
 const reserved=reservations(state);
 for(const offer of sent)if([2,9,11].includes(offer.state))for(const i of offer.itemsToGive)reserved.add(String(i.assetid||i.id));
 const money=inventory.filter(i=>[KEY,'Refined Metal','Reclaimed Metal','Scrap Metal'].includes(i.market_hash_name));
 const free=money.filter(i=>i.tradable&&!reserved.has(String(i.assetid||i.id)));
 const payable=Object.values(state.purchases||{}).filter(r=>['paid','settling','review'].includes(r.status)&&r.buy_trade).reduce((n,r)=>n+priceValue(r.price),0);
 // Reserve all customer liabilities even when some payment assets are already excluded: conservative, never excess withdrawal.
 const liabilities=wallet.points+wallet.withdrawals+payable;
 const rows=Object.values(state.finance||{}).filter(r=>r.done&&r.status==='completed');
 const capital=new Map(rows.filter(r=>r.kind==='capital_in').flatMap(r=>(r.received||[]).map(i=>[String(i.assetid),i])));
 const paid=Object.values(state.outgoing||{}).filter(r=>r.done&&state.offers?.[r.offer]?.status==='completed');
 return {total:value(money),free:value(free),points:wallet.points,pending_withdrawals:wallet.withdrawals,seller_payable:payable,
  capital_in:rows.filter(r=>r.kind==='capital_in').reduce((n,r)=>n+priceValue(r.price),0),
  capital_out:rows.filter(r=>r.kind==='capital_out').reduce((n,r)=>n+priceValue(r.price),0),
  point_deposits:rows.filter(r=>r.kind==='topup').reduce((n,r)=>n+priceValue(r.price),0)+Object.values(state.offers||{}).filter(r=>r.done&&r.status==='credited').reduce((n,r)=>n+r.points,0),
  point_returns:Object.values(state.offers||{}).filter(r=>r.done&&r.kind==='withdrawal'&&r.status==='completed').reduce((n,r)=>n+r.points,0),
  capital_used_for_points:paid.reduce((n,r)=>n+value((r.assets||[]).filter(id=>capital.has(id)).map(id=>capital.get(id))),0),
  capital_used_for_sales:Object.values(state.purchases||{}).filter(r=>r.status==='settled'&&r.funding?.length).reduce((n,r)=>n+priceValue(r.price),0),
  available:Math.max(0,value(free)-liabilities),freeItems:free};
}
function ownerPayment(row,state,inventory,wallet,sent){
 assert(row.owner===OWNER&&row.kind==='capital_out');
 const report=summary(state,inventory,wallet,sent);
 if(priceValue(row.price)>report.available)return null;
 return selectPayment(report.freeItems,row.price,new Set());
}
module.exports={value,priceValue,reservations,summary,ownerPayment};
