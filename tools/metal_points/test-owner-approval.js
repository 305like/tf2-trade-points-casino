'use strict';
const assert=require('node:assert/strict');
const {OWNER,LIMIT,approved,createApproval}=require('./owner-approval');
const {dispatch}=require('./outgoing');
const row={code:'a'.repeat(32),steamid:OWNER,points:LIMIT,url:'https://steamcommunity.com/tradeoffer/new/?partner=78493986&token=abcdefgh'};
async function main(){
  let time=100000,connected=true,saves=0,refunds=0;
  const state={},sent=[];
  const deps={state,save(){saves++;},now:()=>time,online:()=>connected,
    async send(text){sent.push(text);return{server_timestamp:new Date(time)};},
    async api(b){assert.equal(b.action,'reject');refunds++;return{status:'refunded'};}};
  const gate=createApproval(deps);
  const message=(text,id=OWNER,t=time)=>({steamid_friend:{getSteamID64:()=>id},message:text,server_timestamp:new Date(t),chat_entry_type:1});
  assert(approved(state,{...row,points:5750}));assert(!approved(state,row));
  connected=false;await gate.tick([row]);assert.equal(sent.length,0);
  connected=true;await gate.tick([row,{...row,code:'b'.repeat(32)}]);assert.equal(sent.length,1);
  time+=2000;
  assert.equal(await gate.reply(message('예','76561199077147589')),false);
  assert.equal(await gate.reply(message('예',OWNER,100000)),false);
  assert.equal(await gate.reply({...message('예'),local_echo:true}),false);
  assert.equal(await gate.reply(message('yes')),false);
  assert.equal(await gate.reply(message('ㅇㅇ')),true);assert(approved(state,row));assert.equal(saves,1);
  assert(!approved(state,{...row,points:LIMIT+10}));
  assert(!approved(state,{...row,steamid:'76561199077147589'}));
  assert.equal(await gate.reply(message('예')),false);
  const second={...row,code:'b'.repeat(32)};
  time+=11000;await gate.tick([second]);time+=2000;
  assert.equal(await gate.reply(message('아니오')),true);assert(!approved(state,second));
  await gate.tick([second]);await gate.tick([second]);assert.equal(refunds,1);
  const third={...row,code:'c'.repeat(32)};
  time+=11000;await gate.tick([third]);gate.disconnected();time+=1000;
  assert.equal(await gate.reply(message('예')),false);
  await gate.tick([third]);time+=600001;assert.equal(await gate.reply(message('예')),false);
  // The actual send path must block high withdrawals before touching inventory/Steam.
  let sends=0;
  await dispatch({requests:[third],sent:[],inventory:[],state,save(){},manager:{createOffer(){sends++;}},call(){},processOffer(){},hasTradeHold(){},log(){},canApprove:r=>approved(state,r)});
  assert.equal(sends,0);
  for(const text of ['네','예','ㅇㅇ','ㄴㄴ','아니오','아니']) {
    const s={};const g=createApproval({...deps,state:s});await g.tick([row]);time+=2000;
    assert.equal(await g.reply(message(text)),true);
    assert.equal(s.approvals[row.code].decision,['네','예','ㅇㅇ'].includes(text)?'yes':'no');
  }
  console.log('Owner approval: 5760 boundary, pinned SteamID, six replies, single prompt, replay/echo/offline/timeout, durable denial and send gate PASS');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
