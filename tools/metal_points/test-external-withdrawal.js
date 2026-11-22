'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const policy=require('./deposit-policy');
const text=fs.readFileSync(__dirname+'/deposit-bot.js','utf8');
const body=text.slice(text.indexOf('async function processOffer('),text.indexOf('async function processWithdrawal('));
const states={Active:2,CreatedNeedsConfirmation:9};
async function main(){
  const state={offers:{},outgoing:{}};const methods=[];
  const fn=new Function('ready','busy','state','Manager','call','log','deposit','api','processWithdrawal','failure','fs','path','dir','shop','checkout','returns','finance',body+';return processOffer;')(
    true,new Set(),state,{ETradeOfferState:states},async(o,m)=>methods.push(m),()=>{},policy.deposit,async()=>({ready:false}),async()=>methods.push('authorized'),()=>{throw Error('unexpected failure');},{writeFileSync(){}},{join(){return'';}},'',{process:async()=>false},{process:async()=>false},{process:async()=>false},{process:async()=>false});
  const metal={appid:440,contextid:'2',assetid:'1',amount:1,market_hash_name:'Refined Metal'};
  const offer={id:'123',state:2,isOurOffer:false,itemsToGive:[metal],itemsToReceive:[],message:'WITHDRAW '+'a'.repeat(32),partner:{getSteamID64:()=> '76561198038759714'}};
  await fn(offer);assert.deepEqual(methods,['decline']);
  await fn({...offer,isOurOffer:true});assert.deepEqual(methods,['decline','cancel']);
  await fn({...offer,isOurOffer:true,state:9});assert.equal(methods.at(-1),'cancel');
  const before=methods.length;
  await fn({...offer,itemsToGive:[],itemsToReceive:[metal],message:''});assert.equal(methods.length,before+1);assert.equal(methods.at(-1),'decline','item-funded point deposits remain disabled');
  await fn({...offer,itemsToGive:[],itemsToReceive:[{...metal,market_hash_name:'Mann Co. Supply Crate Key'}]});assert.equal(methods.at(-1),'decline');
  state.outgoing.a={offer:'123'};
  await fn({...offer,isOurOffer:true,message:''});assert.equal(methods.at(-1),'authorized');
  console.log('External requests: inbound withdrawals declined, manual outgoing canceled, unsolicited metal/key point deposits rejected PASS');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
