#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include "scratch_lottery_3d.inc"
#define MODEL "models/player/engineer.mdl"
public Plugin myinfo={name="Scratch Lottery Test",author="Codex",description="Private in-world suspicious scratch tickets",version="0.2.2"};
int npc=INVALID_ENT_REFERENCE,previous[MAXPLAYERS+1];
float nextUse[MAXPLAYERS+1];
ArrayList menus;bool ending;
bool Player(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&IsPlayerAlive(c);}
bool Admin(int c){return Player(c)&&(GetUserFlagBits(c)&(ADMFLAG_GENERIC|ADMFLAG_ROOT))!=0&&CheckCommandAccess(c,"sm_scratch_spawn",ADMFLAG_GENERIC);}
int Npc(){int e=EntRefToEntIndex(npc);return e>MaxClients&&IsValidEntity(e)?e:-1;}
int Rank(int roll){return roll<5?1:roll<15?2:roll<30?3:roll<50?4:roll<75?5:0;}
public void OnPluginStart(){
 if(FindConVar("hostport").IntValue!=27019)SetFailState("Test 27019 only");
 menus=new ArrayList();RegAdminCmd("sm_scratch_spawn",Spawn,ADMFLAG_GENERIC);RegAdminCmd("sm_scratch_remove",Remove,ADMFLAG_GENERIC);RegAdminCmd("sm_scratch_status",Status,ADMFLAG_GENERIC);
 AddCommandListener(Chat,"say");AddCommandListener(Chat,"say_team");AddCommandListener(Voice,"voicemenu");
 InitTicket();HookEvent("player_death",TicketDeath);HookEvent("player_spawn",TicketDeath);
 for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c))OnClientPutInServer(c);
 int bins[6];for(int i=0;i<100;i++)bins[Rank(i)]++;
 if(bins[0]!=25||bins[1]!=5||bins[2]!=10||bins[3]!=15||bins[4]!=20||bins[5]!=25)SetFailState("Scratch probability test failed");
}
public void OnMapStart(){PrecacheModel(MODEL,true);CacheTickets();npc=INVALID_ENT_REFERENCE;}
public void OnClientPutInServer(int c){previous[c]=0;nextUse[c]=0.0;active[c]=false;partCount[c]=0;SDKHook(c,SDKHook_OnTakeDamage,TicketDamage);}
public void OnClientDisconnect(int c){CloseTicket(c);}
void Clear(){int e=Npc();npc=INVALID_ENT_REFERENCE;if(e!=-1)RemoveEntity(e);}
public void OnMapEnd(){for(int c=1;c<=MaxClients;c++)CloseTicket(c);Clear();}
public void OnPluginEnd(){ending=true;for(int c=1;c<=MaxClients;c++)CloseTicket(c);while(menus.Length){int i=menus.Length-1;Menu m=view_as<Menu>(menus.Get(i));menus.Erase(i);delete m;}delete menus;Clear();}
public bool Trace(int e,int mask,any c){return e==0||e>MaxClients;}
bool Looking(int c){
 if(!Player(c)||Npc()==-1)return false;
 float p[3],a[3],hit[3];GetClientEyePosition(c,p);GetClientEyeAngles(c,a);
 Handle tr=TR_TraceRayFilterEx(p,a,MASK_SOLID,RayType_Infinite,Trace,c);TR_GetEndPosition(hit,tr);bool found=TR_GetEntityIndex(tr)==Npc()&&GetVectorDistance(p,hit)<=150.0;delete tr;return found;
}
public Action Spawn(int c,int args){
 if(!Admin(c))return Plugin_Handled;
 float p[3],a[3],hit[3],n[3];GetClientEyePosition(c,p);GetClientEyeAngles(c,a);Handle tr=TR_TraceRayFilterEx(p,a,MASK_SOLID,RayType_Infinite,Trace,c);
 bool found=TR_DidHit(tr)&&!TR_StartSolid(tr);TR_GetEndPosition(hit,tr);TR_GetPlaneNormal(tr,n);delete tr;
 if(!found||n[2]<0.7||GetVectorDistance(p,hit)>1000.0){ReplyToCommand(c,"[복권] 가까운 평평한 바닥을 보세요.");return Plugin_Handled;}
 hit[2]+=2.0;float mins[3]={-24.0,-24.0,0.0},maxs[3]={24.0,24.0,82.0};tr=TR_TraceHullFilterEx(hit,hit,mins,maxs,MASK_SOLID,Trace,c);bool blocked=TR_StartSolid(tr)||TR_DidHit(tr);delete tr;if(blocked){ReplyToCommand(c,"[복권] 설치 공간이 막혔습니다.");return Plugin_Handled;}
 int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return Plugin_Handled;DispatchKeyValue(e,"model",MODEL);DispatchKeyValue(e,"solid","6");DispatchKeyValue(e,"DefaultAnim","stand_PRIMARY");
 if(!DispatchSpawn(e)){RemoveEntity(e);return Plugin_Handled;}SetEntProp(e,Prop_Data,"m_takedamage",0);SetEntProp(e,Prop_Send,"m_nSkin",1);a[0]=a[2]=0.0;a[1]+=180.0;TeleportEntity(e,hit,a,NULL_VECTOR);Clear();npc=EntIndexToEntRef(e);
 ReplyToCommand(c,"[복권] 판매 NPC 설치 완료. E 또는 메딕 호출키로 구매하세요.");return Plugin_Handled;
}
public Action Remove(int c,int args){if(Admin(c))Clear();return Plugin_Handled;}
bool Use(int c){
 if(c>0&&c<=MaxClients&&active[c])return true;
 if(!Looking(c))return false;if(GetGameTime()<nextUse[c])return true;nextUse[c]=GetGameTime()+0.5;
 Menu m=new Menu(Buy);menus.Push(m);m.SetTitle("스크래치 복권 판매");m.AddItem("buy","스크래치 복권 구매 (0원)");m.Display(c,20);return true;
}
public int Buy(Menu m,MenuAction action,int c,int item){
 if(action==MenuAction_End){if(!ending){int i=menus.FindValue(m);if(i!=-1){menus.Erase(i);delete m;}}return 0;}
 if(ending||action!=MenuAction_Select||!Looking(c)||item!=0)return 0;
 StartTicket(c);return 0;
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float vel[3],float angles[3],int &weapon,int &subtype,int &cmdnum,int &tickcount,int &seed,int mouse[2]){
 int old=previous[c];previous[c]=buttons;
 if(active[c]){
  if(!Player(c)||(buttons&IN_RELOAD)||GetGameTime()>expires[c]){CloseTicket(c);return Plugin_Continue;}
  ScratchMove(c,angles);return Plugin_Continue;
 }
 if((buttons&IN_USE)&&!(old&IN_USE)&&Use(c)){buttons&=~IN_USE;return Plugin_Changed;}return Plugin_Continue;
}
public Action Voice(int c,const char[] cmd,int args){char a[8],b[8];GetCmdArg(1,a,sizeof(a));GetCmdArg(2,b,sizeof(b));return StrEqual(a,"0")&&StrEqual(b,"0")&&Use(c)?Plugin_Handled:Plugin_Continue;}
public Action Chat(int c,const char[] cmd,int args){char text[64];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);if(StrEqual(text,"!복권설치")){Spawn(c,0);return Plugin_Handled;}if(StrEqual(text,"!복권삭제")){Remove(c,0);return Plugin_Handled;}return Plugin_Continue;}
public Action Status(int c,int args){int count;for(int i=1;i<=MaxClients;i++)if(active[i])count++;ReplyToCommand(c,"Scratch 0.2.2 npc=%d assets_ready=%d sessions=%d probabilities=5/10/15/20/25/25 winning_panel_threshold=75 pixel_area=quarter economy=disabled controls=free",Npc(),assetsReady,count);return Plugin_Handled;}
