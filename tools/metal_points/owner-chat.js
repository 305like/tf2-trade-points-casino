'use strict';
const fs=require('node:fs');
const path=require('node:path');
const SteamUser=require('steam-user');
const {OWNER,createApproval}=require('./owner-approval');
module.exports=function({dir,state,save,api,log}) {
  const file=path.join(dir,'chat-refresh-token');
  const user=new SteamUser({dataDirectory:path.join(dir,'chat'),autoRelogin:true,renewRefreshTokens:false,promptSteamGuardCode:false});
  let connected=false;
  const send=text=>user.chat.sendFriendMessage(OWNER,text,{containsBbCode:false});
  const approvals=createApproval({state,save,api,send,online:()=>connected});
  function health(status){fs.writeFileSync(path.join(dir,'chat-health.json'),JSON.stringify({time:Date.now(),status,owner:OWNER}),{mode:0o600});}
  user.on('loggedOn',()=>{
    if(user.steamID.getSteamID64()!=='76561199077147589') {user.logOff();health('wrong-account');return;}
    connected=true;user.setPersona(SteamUser.EPersonaState.Online);health('online');log('Owner approval Steam chat connected');
  });
  user.on('friendsList',()=>{
    if(user.myFriends[OWNER]!==SteamUser.EFriendRelationship.Friend) {
      user.addFriend(OWNER,err=>health(err?'owner-friend-unavailable':'owner-friend-requested'));
    } else send('출금 안전 확인이 연결되었습니다. 64정(5760포인트) 이상 출금은 이 채팅에서 주인의 승인을 받은 뒤 진행합니다. 외부 금속 충전은 그대로 허용합니다.').catch(()=>health('message-failed'));
  });
  user.chat.on('friendMessage',message=>void approvals.reply(message).catch(()=>log('Owner approval reply failed; withdrawal remains gated')));
  user.on('disconnected',()=>{connected=false;approvals.disconnected();health('disconnected');});
  user.on('error',()=>{connected=false;approvals.disconnected();health('login-error');});
  user.on('steamGuard',()=>{connected=false;health('authentication-required');});
  if(fs.existsSync(file)) {
    try {user.logOn({refreshToken:fs.readFileSync(file,'utf8').trim(),steamID:'76561199077147589',logonID:27020,machineName:'Metal Points Owner Approval'});}
    catch {health('authentication-required');}
  } else health('authentication-required');
  return {...approvals,stop(){user.logOff();}};
};
