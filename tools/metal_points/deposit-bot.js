'use strict';
// Dedicated incoming-metal entrypoint; upstream market trading is not started.
process.umask(0o077);
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {LoginSession, EAuthTokenPlatformType} = require('steam-session');
const Community = require('@tf2autobot/steamcommunity');
const Manager = require('@tf2autobot/tradeoffer-manager');
const {deposit, receipt, withdrawal, withdrawalReceipt, hasTradeHold} = require('./deposit-policy');
const {dispatch}=require('./outgoing');
const {approved}=require('./owner-approval');
const dir = path.resolve(__dirname, '../.metal-points-private');
const config = JSON.parse(fs.readFileSync(path.join(dir,'config.json'),'utf8'));
assert.equal(config.steamid,'76561199077147589');
assert.equal(config.endpoint,'https://trade.santasrv.com/metal-points/ingress.php');
assert(/^[a-f0-9]{64}$/.test(config.apiToken));
const stateFile = path.join(dir,'state.json');
const ledgerBackup=require('./ledger-backup');
let state = ledgerBackup.load(stateFile);
assert(state && state.offers && !Array.isArray(state.offers));
ledgerBackup.daily(dir,state);
function save() {
 try {
  const fd = fs.openSync(stateFile+'.tmp','w',0o600);
  try {fs.writeFileSync(fd, JSON.stringify(state)); fs.fsyncSync(fd);} finally {fs.closeSync(fd);}
  fs.renameSync(stateFile+'.tmp',stateFile);
  const d=fs.openSync(dir,'r'); try {fs.fsyncSync(d);} finally {fs.closeSync(d);}
 } catch {console.error('FATAL: durable state write failed; stopping trading'); process.exit(1);}
}
function log(message) { console.log(new Date().toISOString(),message); }
// Never log Steam error bodies: they can contain session cookies and tokens.
function failure(where, e) { log(`${where}: failed (${Number.isInteger(e?.eresult)?e.eresult:'retry pending'})`); }
const community = new Community();
fs.mkdirSync(path.join(dir,'manager'),{recursive:true,mode:0o700});
const manager = new Manager({community, language:'en', useAccessToken:true, pollInterval:15000, dataDirectory:path.join(dir,'manager'), savePollData:true});
const session = new LoginSession(EAuthTokenPlatformType.MobileApp);
session.refreshToken = config.refreshToken;
const busy = new Set();
let ready = false, loggingIn = false;
const call = (object, method, ...args) => new Promise((resolve,reject)=>object[method](...args,(err,...out)=>err?reject(err):resolve(out)));
async function api(body) {
  const r=await fetch(config.endpoint,{method:'POST',redirect:'error',headers:{'Content-Type':'application/json','X-Metal-Token':config.apiToken},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  assert.equal(r.status,200,'point ingress unavailable');
  const result=await r.json(); assert.equal(result.ok,true); return result;
}
const ownerChat=require('./owner-chat')({dir,state,save,api,log});
async function shopApi(body){
 const r=await fetch('https://trade.santasrv.com/bot-shop/bot-api.php',{method:'POST',redirect:'error',headers:{'Content-Type':'application/json','X-Metal-Token':config.apiToken},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 assert.equal(r.status,200);const result=await r.json();assert.equal(result.ok,true);return result;
}
async function verifyLedger(){
 try{const {rows}=await shopApi({action:'ledger'});await checkout.recoverCompletedReceipts(rows);require('./ledger-audit').verify(state,rows);}
 catch(e){ready=false;throw e;}
}
const shop=require('./shop-intake').create({state,save,api:shopApi,manager,call,community,identitySecret:config.identitySecret,hasTradeHold,log});
const checkout=require('./shop-checkout').create({state,save,api:shopApi,manager,call,community,identitySecret:config.identitySecret,hasTradeHold,log});
const returns=require('./shop-returns').create({state,save,api:shopApi,manager,call,community,identitySecret:config.identitySecret,hasTradeHold,log});
const finance=require('./shop-finance').create({state,save,api:shopApi,pointApi:api,manager,call,community,identitySecret:config.identitySecret,hasTradeHold,log});
async function login() {
  if (loggingIn) return;
  loggingIn=true; ready=false;
  try {
    const cookies=await session.getWebCookies();
    assert.equal(session.steamID.getSteamID64(),config.steamid);
    await call(manager,'setCookies',cookies);
    await verifyLedger();
    ready=true;
    log('Steam web login verified; metal deposits and ledger-reserved withdrawals ONLY');
    const [url]=await call(community,'getTradeURL');
    assert(typeof url==='string' && url.startsWith('https://steamcommunity.com/tradeoffer/new/?'));
    fs.writeFileSync(path.join(dir,'trade-url.txt'),url+'\n',{mode:0o600});
    await reconcile();
  } catch(e) { failure('Steam session',e); }
  finally {loggingIn=false;}
}
async function processOffer(offer) {
  if (!ready || busy.has(offer.id)) return;
  busy.add(offer.id);
  try {
    if(await finance.process(offer)||await returns.process(offer)||await checkout.process(offer)||await shop.process(offer))return;
    if(offer.isOurOffer && Object.values(state.outgoing||{}).some(r=>r.offer===offer.id&&!r.done)) {
      fs.writeFileSync(path.join(dir,'outgoing-health.json'),JSON.stringify({time:Date.now(),id:offer.id,state:offer.state,messagePresent:!!offer.message}),{mode:0o600});
    }
    const knownOutgoing=offer.isOurOffer&&Object.values(state.outgoing||{}).some(r=>r.offer===offer.id&&!r.done);
    if(offer.isOurOffer) {
      if(knownOutgoing) {await processWithdrawal(offer);return;}
      if([Manager.ETradeOfferState.Active,Manager.ETradeOfferState.CreatedNeedsConfirmation].includes(offer.state)) {
        await call(offer,'cancel');log(`External outgoing offer ${offer.id}: canceled`);
      }
      return;
    }
    if(offer.itemsToGive.length>0) {
      if(offer.state===Manager.ETradeOfferState.Active) {await call(offer,'decline');log(`External withdrawal ${offer.id}: declined`);}
      return;
    }
    // Item-funded points are disabled. Unrequested incoming gifts cannot fund game balances.
    if(offer.state===Manager.ETradeOfferState.Active){await call(offer,'decline');return;}
    let wanted;
    try {wanted=deposit(offer);} catch {
      if(offer.state===Manager.ETradeOfferState.Active) await call(offer,'decline');
      return;
    }
    let record=state.offers[offer.id];
    if (record?.done) return;
    if (record) assert(record.steamid===wanted.steamid && record.points===wanted.points,'offer changed');
    if (offer.state===Manager.ETradeOfferState.Active) {
      if (!(await api({health:true})).ready) return;
      const [me,them]=await call(offer,'getUserDetails');
      if (hasTradeHold(offer,me,them)) {log(`Offer ${offer.id}: waiting, escrow days bot=${me.escrowDays ?? 'unknown'} sender=${them.escrowDays ?? 'unknown'}`); return;}
      if (!record) {state.offers[offer.id]=wanted; save(); record=wanted;}
      save();
      const [result]=await call(offer,'accept');
      if (result==='pending') await call(community,'acceptConfirmationForObject',config.identitySecret,offer.id);
      log(`Offer ${offer.id}: acceptance requested, not credited yet`);
      return;
    }
    if (!record) return;
    if (offer.state===Manager.ETradeOfferState.CreatedNeedsConfirmation) {
      await call(community,'acceptConfirmationForObject',config.identitySecret,offer.id); return;
    }
    if (offer.state===Manager.ETradeOfferState.InEscrow) return;
    if (offer.state!==Manager.ETradeOfferState.Accepted) {
      if ([Manager.ETradeOfferState.Declined,Manager.ETradeOfferState.Canceled,Manager.ETradeOfferState.Expired,Manager.ETradeOfferState.InvalidItems,Manager.ETradeOfferState.CanceledBySecondFactor].includes(offer.state)) {
        record.done=true; record.status='not-completed'; save();
      }
      return;
    }
    const [status,,received,given]=await call(offer,'getExchangeDetails');
    const verified=receipt(offer,status,received,given);
    const result=await api(verified);
    if(result.status==='credited') {record.done=true; record.trade=verified.trade; record.status='credited'; save(); log(`Offer ${offer.id}: ${verified.points} points credited`);}
  } catch(e) {failure(`Offer ${offer.id}`,e);}
  finally {busy.delete(offer.id);}
}
async function processWithdrawal(offer) {
  let wanted;
  const outgoing=!!offer.isOurOffer;
  const boundCode=outgoing?(Object.entries(state.outgoing||{}).find(([,r])=>r.offer===offer.id)?.[0]||null):null;
  try {wanted=withdrawal(offer,outgoing,boundCode);} catch {
    if(outgoing) log(`Withdrawal ${offer.id}: validation pending; metalNames=${offer.itemsToGive.every(i=>!!i.market_hash_name)} context=${offer.itemsToGive.every(i=>String(i.contextid)==='2')} amount=${offer.itemsToGive.every(i=>String(i.amount)==='1')}`);
    return;
  }
  if(outgoing) {
    const intent=state.outgoing?.[wanted.code];
    if(!intent || intent.steamid!==wanted.steamid || intent.points!==wanted.points || (intent.offer&&intent.offer!==offer.id)) return;
    const assets=offer.itemsToGive.map(i=>String(i.assetid||i.id)).sort();
    assert.deepEqual(assets,[...intent.assets].sort());
    if(!approved(state,wanted)) return;
    intent.offer=offer.id; save();
  }
  let row=state.offers[offer.id];
  if(row?.done) return;
  if(!row) {
    if((!outgoing&&offer.state!==Manager.ETradeOfferState.Active) || !(await api({health:true})).ready) return;
    row={...wanted,kind:'withdrawal'}; state.offers[offer.id]=row; save();
  }
  assert(row.kind==='withdrawal' && row.code===wanted.code && row.points===wanted.points && row.steamid===wanted.steamid);
  const claim=await api({...wanted,action:outgoing?'bind':'claim'});
  if(claim.status==='queued') return;
  if(claim.status==='denied') {row.done=true; row.status='denied'; save(); log(`Withdrawal ${offer.id}: no matching reservation`); return;}
  assert.equal(claim.status,'authorized');
  if(offer.state===Manager.ETradeOfferState.Active) {
    if(outgoing) {await api({...wanted,action:'sent'}); return;}
    const [me,them]=await call(offer,'getUserDetails');
    if(hasTradeHold(offer,me,them)) {log(`Withdrawal ${offer.id}: escrow restriction; cancel offer to refund reservation`); return;}
    save();
    const [result]=await call(offer,'accept');
    if(result==='pending') await call(community,'acceptConfirmationForObject',config.identitySecret,offer.id);
    log(`Withdrawal ${offer.id}: acceptance requested`); return;
  }
  if(offer.state===Manager.ETradeOfferState.CreatedNeedsConfirmation) {
    await call(community,'acceptConfirmationForObject',config.identitySecret,offer.id); return;
  }
  let settlement;
  if(offer.state===Manager.ETradeOfferState.Accepted) {
    const [status,,received,given]=await call(offer,'getExchangeDetails');
    settlement={...withdrawalReceipt(offer,status,received,given,outgoing,boundCode),result:'completed'};
  } else if([Manager.ETradeOfferState.Declined,Manager.ETradeOfferState.Canceled,Manager.ETradeOfferState.Expired,Manager.ETradeOfferState.InvalidItems,Manager.ETradeOfferState.CanceledBySecondFactor].includes(offer.state)) {
    // Terminal non-acceptance only: never refund on timeout, escrow or ambiguous network errors.
    settlement={...wanted,trade:'0',result:'failed'};
  } else return;
  const result=await api({...settlement,action:'settle'});
  if(result.status==='settled') {row.done=true; row.status=settlement.result; if(outgoing) state.outgoing[wanted.code].done=true; save(); log(`Withdrawal ${offer.id}: ${row.status}`);}
}
let reconciling=false;
async function reconcile() {
  if (!ready || reconciling || shop.isBusy()) return;
  reconciling=true;
  try {
    ledgerBackup.daily(dir,state);
    await verifyLedger();
    try{await shop.tick();}catch(e){failure('Shop intake',e);}
    try{await checkout.tick();}catch(e){failure('Shop checkout',e);}
    try{await returns.tick();}catch(e){failure('Shop return',e);}
    try{await finance.tick();}catch(e){ready=false;failure('Shop finance',e);return;}
    // Recover persisted sends even if validation failed before state.offers was populated.
    const pending=new Set(Object.entries(state.offers).filter(([,r])=>!r.done).map(([id])=>id));
    for(const row of Object.values(state.outgoing||{})) if(!row.done&&row.offer) pending.add(row.offer);
    for (const id of pending) {
      try { const [offer]=await call(manager,'getOffer',id); await processOffer(offer); }
      catch(e) {failure(`Reconcile ${id}`,e);}
    }
    // Full active sweep also retries offers blocked by escrow or a temporarily offline game server.
    const [activeSent,received]=await call(manager,'getOffers',Manager.EOfferFilter.ActiveOnly);
    for(const offer of received) await processOffer(offer);
    for(const offer of activeSent) await processOffer(offer);
    const queue=await api({action:'outgoing'});
    await ownerChat.tick(queue.requests.concat(checkout.approvals(),returns.approvals()));
    // Pending intake can introduce new asset IDs; wait until custody is reconciled.
    if(queue.requests.length&&!checkout.uncertain()&&!Object.values(state.shop||{}).some(r=>!r.done)) {
      // Historical offers recover a send accepted by Steam before a local crash.
      const starts=Object.values(state.outgoing||{}).filter(r=>!r.done).map(r=>r.started);
      const cutoff=new Date((starts.length?Math.min(...starts):Date.now())-86400000);
      const [sent]=await call(manager,'getOffers',Manager.EOfferFilter.All,cutoff);
      const [inventory]=await call(manager,'getInventoryContents',440,'2',true);
      const custody=new Set([...shop.reserved(),...checkout.reserved(),...finance.reserved()]);
      await dispatch({requests:queue.requests,sent,inventory:inventory.filter(i=>!custody.has(String(i.assetid||i.id))),state,save,manager,call,processOffer,hasTradeHold,log,canApprove:row=>approved(state,row)});
    }
  } catch(e) {failure('Reconcile',e);}
  finally {reconciling=false;}
}
manager.on('newOffer',offer=>void processOffer(offer));
manager.on('receivedOfferChanged',offer=>void processOffer(offer));
manager.on('sentOfferChanged',offer=>void processOffer(offer));
manager.on('sessionExpired',()=>void login());
manager.on('pollFailure',e=>failure('Steam polling',e));
let firstPoll=true;
manager.on('pollSuccess',()=>{
  fs.writeFileSync(path.join(dir,'poll-health.json'),JSON.stringify({time:Date.now(),steamid:config.steamid}),{mode:0o600});
  if(firstPoll) {firstPoll=false; log('Steam trade offer polling verified');}
});
setInterval(()=>void reconcile(),30000);
setInterval(()=>{if(ready&&!reconciling)void shop.pollNew().catch(e=>failure('New intake polling',e));},5000);
setInterval(()=>void login(),20*60*1000);
setInterval(()=>{if(!ready) void login();},60000);
process.on('SIGTERM',()=>{ownerChat.stop();manager.shutdown(); process.exit(0);});
process.on('SIGINT',()=>{ownerChat.stop();manager.shutdown(); process.exit(0);});
void login();
