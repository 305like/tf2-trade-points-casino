'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const policy=require('./deposit-policy');
const source=fs.readFileSync(__dirname+'/deposit-bot.js','utf8');
const body=source.slice(source.indexOf('async function processWithdrawal('),source.indexOf('let reconciling=false;'));
const states={Active:2,Accepted:3,Expired:5,Canceled:6,Declined:7,InvalidItems:8,CreatedNeedsConfirmation:9,CanceledBySecondFactor:10,InEscrow:11};
async function scenario(finalState) {
  const code='a'.repeat(32),sid='76561199077147589';
  const item={appid:440,contextid:'2',assetid:'1',amount:'1',market_hash_name:'Refined Metal'};
  const state={offers:{},outgoing:{[code]:{steamid:sid,points:90,assets:['1'],offer:'123'}}};
  const offer={id:'123',tradeID:'456',isOurOffer:true,state:9,message:'',itemsToGive:[item],itemsToReceive:[],partner:{getSteamID64:()=>sid}};
  const actions=[],methods=[];
  const api=async b=>{
    if(b.health)return{ready:true}; actions.push(b);
    return {status:b.action==='settle'?'settled':'authorized'};
  };
  const call=async (o,method)=>{
    methods.push(method);
    if(method==='getExchangeDetails') return [3,null,[],[item]];
    assert.equal(method,'acceptConfirmationForObject');return[];
  };
  const fn=new Function('approved','assert','withdrawal','withdrawalReceipt','hasTradeHold','state','Manager','api','call','community','config','save','log',body+';return processWithdrawal;')(
    require('./owner-approval').approved,assert,policy.withdrawal,policy.withdrawalReceipt,policy.hasTradeHold,state,{ETradeOfferState:states},api,call,{}, {identitySecret:'test'},()=>{},()=>{});
  await fn(offer);
  assert.deepEqual(methods,['acceptConfirmationForObject']);
  assert(!actions.some(a=>a.action==='sent'));
  offer.state=2;await fn(offer);
  assert(actions.some(a=>a.action==='sent'));
  offer.state=11;await fn(offer);
  assert(!actions.some(a=>a.action==='settle'));
  offer.state=finalState;await fn(offer);
  assert.equal(actions.filter(a=>a.action==='settle').length,1);
  assert.equal(actions.at(-1).result,finalState===3?'completed':'failed');
  assert(state.outgoing[code].done);
  await fn(offer);assert.equal(actions.filter(a=>a.action==='settle').length,1);
  assert(!methods.includes('accept'),'never accept our own offers');
}
Promise.all([scenario(3),scenario(7)]).then(()=>console.log('Bot actual withdrawal handler: confirmation before sent notice, escrow retained, completion/cancel settled once PASS')).catch(e=>{console.error(e);process.exitCode=1;});
