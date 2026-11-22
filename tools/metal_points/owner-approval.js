'use strict';
const assert=require('node:assert/strict');
const {validateRequest}=require('./outgoing');
const OWNER='76561198038759714';
const LIMIT=5760;
function approved(state,row) {
  if(row.points<LIMIT) return true;
  const a=state.approvals?.[row.code];
  return !!a&&a.decision==='yes'&&a.steamid===row.steamid&&a.points===row.points;
}
function createApproval({state,save,send,api,online,now=Date.now}) {
  state.approvals ||= {};
  let active=null,working=false,cooldown=0;
  async function tick(requests) {
    if(working) return;
    working=true;
    try {
      for(const row of requests) {
        validateRequest(row);
        if(row.points<LIMIT) continue;
        const old=state.approvals[row.code];
        if(old) {
          assert(old.steamid===row.steamid&&old.points===row.points);
          if(old.decision==='no'&&!old.refunded) {
            if(row.kind==='shop'||row.kind==='return'){
              const target=row.kind==='shop'?state.purchases?.[row.code]:state.shopReturns?.[row.code];
              assert(target&&!target.payout_started&&!target.send_started);
              target.review=true;old.refunded=true;save();continue;
            }
            const result=await api({action:'reject',code:row.code,steamid:row.steamid,points:row.points});
            if(result.status==='refunded') {old.refunded=true;save();}
          }
          continue;
        }
        if(active&&active.expires<=now()) active=null;
        if(active||!online()||cooldown>now()) continue;
        const amount=['shop','return'].includes(row.kind)?row.label:`${row.points}포인트 (정제금속 ${row.points/90}개 상당)`;
        const sent=await send(`${row.steamid} 님이 ${amount}를 출금하려고 합니다. 수락하시겠습니까?\n요청 ${row.code.slice(0,8)} · 승인: 네 / ㅇㅇ / 예 · 취소: ㄴㄴ / 아니오 / 아니\n현재 이 요청 1건에만 답장이 적용됩니다. 10분 뒤에는 다시 확인합니다.`);
        assert(sent.server_timestamp instanceof Date);
        active={...row,promptTime:sent.server_timestamp.getTime(),expires:now()+600000};
      }
    } finally {working=false;}
  }
  async function reply(message) {
    if(working||!active||!online()||active.expires<=now()||message.local_echo||message.chat_entry_type!==1||message.steamid_friend?.getSteamID64()!==OWNER) return false;
    const time=message.server_timestamp?.getTime();
    if(!Number.isFinite(time)||time<=active.promptTime||time>now()+60000) return false;
    const text=String(message.message||'').trim();
    const decision=['네','ㅇㅇ','예'].includes(text)?'yes':(['ㄴㄴ','아니오','아니'].includes(text)?'no':null);
    if(!decision) return false;
    working=true;
    try {
      const row=active;
      // Persist the decision before dispatch/refund; never reuse an answer for another request.
      assert(!state.outgoing?.[row.code],'Offer must not exist before owner approval');
      state.approvals[row.code]={steamid:row.steamid,points:row.points,decision,at:now()};
      save();active=null;cooldown=now()+10000;
      await send(decision==='yes'?'승인했습니다. 해당 출금 요청만 진행합니다.':row.kind==='return'?'아이템 자동 반환을 중지했습니다. 아이템은 보관되며 관리자 확인이 필요합니다.':row.kind==='shop'?'정산 자동 지급을 중지했습니다. 판매대금은 보관되며 관리자 확인이 필요합니다.':'취소했습니다. 해당 요청의 예약 포인트를 환불 처리합니다.');
      return true;
    } finally {working=false;}
  }
  return {tick,reply,disconnected(){active=null;}};
}
module.exports={OWNER,LIMIT,approved,createApproval};
