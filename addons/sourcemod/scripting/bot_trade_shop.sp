#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

public Plugin myinfo = {name="Bot Trade Shop", author="Nomyname", description="Game-bound shop session and NPC", version="0.3.0"};
#define NPC_LIMIT 32
#define NPC_MODEL "models/player/engineer.mdl"
int refs[NPC_LIMIT], previous[MAXPLAYERS+1];
float nextUse[MAXPLAYERS+1];
ArrayList menus;
bool ending;
ConVar pageURL;
char placement[PLATFORM_MAX_PATH];

 #include "bot_trade_shop_session.inc"

public void OnPluginStart()
{
    ShopSession_Start();
    menus=new ArrayList();
    for(int i;i<NPC_LIMIT;i++) refs[i]=INVALID_ENT_REFERENCE;
    pageURL=CreateConVar("sm_bottrade_url","","HTTPS product page URL; no secret or player ID in URL",FCVAR_NONE);
    AutoExecConfig(true,"bot_trade_shop");
    RegConsoleCmd("sm_bottrade",OpenCommand);
    RegConsoleCmd("sm_botpoints",PointsCommand);
    RegConsoleCmd("sm_botfunds",FundsCommand);
    RegAdminCmd("sm_bottradenpc",AddCommand,ADMFLAG_ROOT);
    RegAdminCmd("sm_bottradenpcremove",RemoveCommand,ADMFLAG_ROOT);
    AddCommandListener(Medic,"voicemenu");
}
public void OnMapStart()
{
    PrecacheModel(NPC_MODEL,true);
    char map[128],dir[PLATFORM_MAX_PATH]; GetCurrentMap(map,sizeof(map));
    ReplaceString(map,sizeof(map),"/","_"); ReplaceString(map,sizeof(map),"\\","_");
    BuildPath(Path_SM,dir,sizeof(dir),"data/bot_trade_shop");
    if(!DirExists(dir)) CreateDirectory(dir,0755);
    Format(placement,sizeof(placement),"%s/%s.cfg",dir,map);
    for(int i;i<NPC_LIMIT;i++) refs[i]=INVALID_ENT_REFERENCE;
    KeyValues kv=new KeyValues("NPCs");
    if(kv.ImportFromFile(placement)&&kv.GotoFirstSubKey())
    {
        int i; do {float pos[3],ang[3];kv.GetVector("origin",pos);kv.GetVector("angles",ang);SpawnNPC(i++,pos,ang);} while(i<NPC_LIMIT&&kv.GotoNextKey());
    }
    delete kv;
}
public void OnClientPutInServer(int client){ShopSession_Revoke(client);previous[client]=0;nextUse[client]=0.0;}
bool Player(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&!IsFakeClient(c);}
bool Root(int c){return Player(c)&&CheckCommandAccess(c,"sm_bottradenpc",ADMFLAG_ROOT);}
bool SpawnNPC(int slot,const float pos[3],const float ang[3])
{
    int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return false;
    DispatchKeyValue(e,"model",NPC_MODEL);DispatchKeyValue(e,"solid","2");
    DispatchKeyValue(e,"DefaultAnim","stand_LOSER");DispatchKeyValue(e,"targetname","bot_trade_shop_npc");
    DispatchKeyValue(e,"skin","0");
    if(!DispatchSpawn(e)){RemoveEntity(e);return false;}
    TeleportEntity(e,pos,ang,NULL_VECTOR);SetEntityMoveType(e,MOVETYPE_NONE);
    refs[slot]=EntIndexToEntRef(e);return true;
}
bool SaveNPCs()
{
    KeyValues kv=new KeyValues("NPCs");
    for(int i;i<NPC_LIMIT;i++)
    {
        int e=EntRefToEntIndex(refs[i]);if(e==INVALID_ENT_REFERENCE)continue;
        char key[12];IntToString(i,key,sizeof(key));kv.JumpToKey(key,true);
        float pos[3],ang[3];GetEntPropVector(e,Prop_Data,"m_vecAbsOrigin",pos);GetEntPropVector(e,Prop_Data,"m_angRotation",ang);
        kv.SetVector("origin",pos);kv.SetVector("angles",ang);kv.GoBack();
    }
    char temp[PLATFORM_MAX_PATH];Format(temp,sizeof(temp),"%s.new",placement);
    bool ok=kv.ExportToFile(temp);delete kv;
    if(ok)ok=RenameFile(placement,temp);
    if(!ok)LogError("NPC placement save failed: %s",placement);
    return ok;
}
public Action AddCommand(int c,int args)
{
    if(!Root(c)||!IsPlayerAlive(c))return Plugin_Handled;
    int slot=-1;for(int i;i<NPC_LIMIT;i++)if(EntRefToEntIndex(refs[i])==INVALID_ENT_REFERENCE){slot=i;break;}
    if(slot<0){ReplyToCommand(c,"[봇거래] NPC는 최대 32개입니다.");return Plugin_Handled;}
    float start[3],end[3],angle[3],normal[3];GetClientEyePosition(c,start);GetClientEyeAngles(c,angle);
    Handle tr=TR_TraceRayFilterEx(start,angle,MASK_PLAYERSOLID,RayType_Infinite,IgnoreClient,c);
    bool hit=TR_DidHit(tr);TR_GetEndPosition(end,tr);TR_GetPlaneNormal(tr,normal);delete tr;
    if(!hit||GetVectorDistance(start,end)>512.0||normal[2]<0.7){ReplyToCommand(c,"[봇거래] 512유닛 안의 평평한 바닥을 바라보세요.");return Plugin_Handled;}
    end[2]+=1.0;angle[0]=0.0;angle[1]+=180.0;angle[2]=0.0;
    float top[3],mins[3]={-20.0,-20.0,0.0},maxs[3]={20.0,20.0,82.0};top=end;top[2]+=0.1;
    tr=TR_TraceHullFilterEx(end,top,mins,maxs,MASK_PLAYERSOLID,IgnoreClient,c);
    bool blocked=TR_DidHit(tr)||TR_StartSolid(tr);delete tr;
    if(blocked){ReplyToCommand(c,"[봇거래] NPC를 놓을 공간이 부족합니다.");return Plugin_Handled;}
    if(!SpawnNPC(slot,end,angle)){ReplyToCommand(c,"[봇거래] NPC 생성 실패.");return Plugin_Handled;}
    if(!SaveNPCs()){RemoveEntity(EntRefToEntIndex(refs[slot]));refs[slot]=INVALID_ENT_REFERENCE;ReplyToCommand(c,"[봇거래] 저장 실패로 설치를 취소했습니다.");}
    else ReplyToCommand(c,"[봇거래] 설치 완료. NPC를 보고 E 또는 메딕 호출로 이용하세요.");
    return Plugin_Handled;
}
public bool IgnoreClient(int entity,int mask,any client){return entity!=client;}
int AimedSlot(int c)
{
    if(!Player(c)||!IsPlayerAlive(c))return -1;
    float start[3],ang[3],end[3];GetClientEyePosition(c,start);GetClientEyeAngles(c,ang);
    Handle tr=TR_TraceRayFilterEx(start,ang,MASK_SOLID,RayType_Infinite,IgnoreClient,c);
    int e=TR_GetEntityIndex(tr);TR_GetEndPosition(end,tr);delete tr;
    if(e<=MaxClients||GetVectorDistance(start,end)>180.0)return -1;
    for(int i;i<NPC_LIMIT;i++)if(EntRefToEntIndex(refs[i])==e)return i;
    return -1;
}
public Action RemoveCommand(int c,int args)
{
    if(!Root(c))return Plugin_Handled;
    int slot=AimedSlot(c);if(slot<0){ReplyToCommand(c,"[봇거래] 가까운 거래 NPC를 바라보세요.");return Plugin_Handled;}
    int old=refs[slot];refs[slot]=INVALID_ENT_REFERENCE;
    if(!SaveNPCs()){refs[slot]=old;ReplyToCommand(c,"[봇거래] 저장 실패. 삭제하지 않았습니다.");}
    else {RemoveEntity(EntRefToEntIndex(old));ReplyToCommand(c,"[봇거래] NPC 삭제 완료.");}
    return Plugin_Handled;
}
void CloseMenu(Menu menu)
{
    if(menus==null)return;int i=menus.FindValue(menu);if(i<0)return;
    menus.Erase(i);menu.Cancel();delete menu;
}
void ShowShopMenu(int c)
{
    if(ending||!Player(c))return;
    Menu m=new Menu(ShopMenu);menus.Push(m);m.SetTitle("봇거래 상품 안내");
    m.AddItem("open","상품 페이지 열기 (사기 / 팔기)");
    m.Display(c,30);
}
public Action OpenCommand(int c,int args){ShowShopMenu(c);return Plugin_Handled;}
void OpenTab(int c,const char[] tab)
{
    if(!Player(c)||ending)return;
    ShowVGUIPanel(c,"info",INVALID_HANDLE,false);
    DataPack pack;CreateDataTimer(0.15,OpenPage,pack,TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientSerial(c));pack.WriteString(tab);
}
public Action PointsCommand(int c,int args){OpenTab(c,"points");return Plugin_Handled;}
public Action FundsCommand(int c,int args)
{
    char id[32];
    if(!Player(c))return Plugin_Handled;
    if(!GetClientAuthId(c,AuthId_SteamID64,id,sizeof(id),true)||!StrEqual(id,"76561198038759714"))PrintToChat(c,"[봇거래] 소유자 전용 기능입니다.");
    else OpenTab(c,"treasury");
    return Plugin_Handled;
}
public int ShopMenu(Menu menu,MenuAction action,int c,int item)
{
    if(action==MenuAction_End){CloseMenu(menu);return 0;}
    if(action!=MenuAction_Select||ending||!Player(c))return 0;
    char key[16];menu.GetItem(item,key,sizeof(key));
    if(StrEqual(key,"open"))
    {
        ShowVGUIPanel(c,"info",INVALID_HANDLE,false);
        DataPack pack;CreateDataTimer(0.15,OpenPage,pack,TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(GetClientSerial(c));
        pack.WriteString("sell");
    }
    return 0;
}
public Action OpenPage(Handle timer,DataPack pack)
{
    pack.Reset();int c=GetClientFromSerial(pack.ReadCell());
    char tab[16];pack.ReadString(tab,sizeof(tab));
    if(!Player(c)||ending)return Plugin_Stop;
    char url[256];pageURL.GetString(url,sizeof(url));
    if(StrContains(url,"https://")!=0||strlen(url)>130||StrContains(url,"?")!=-1||StrContains(url,"#")!=-1)
    {PrintToChat(c,"[봇거래] 관리자가 상품 페이지 주소를 설정해야 합니다.");return Plugin_Stop;}
    if(!ShopSession_Issue(c)){PrintToChat(c,"[봇거래] 게임 계정을 확인하지 못했습니다. 잠시 후 다시 열어 주세요.");return Plugin_Stop;}
    int length=strlen(url);if(length>0&&url[length-1]!='/')StrCat(url,sizeof(url),"/");
    Format(url,sizeof(url),"%sgame.php?tab=%s#%s",url,tab,shopToken[c]);
    if(strlen(url)>159){ShopSession_Revoke(c);PrintToChat(c,"[봇거래] 상점 주소가 창 표시 한도를 넘습니다.");return Plugin_Stop;}
    KeyValues panel=new KeyValues("data");panel.SetString("title","Bot Trade");panel.SetNum("type",MOTDPANEL_TYPE_URL);
    panel.SetString("msg",url);panel.SetNum("customsvr",1);panel.SetNum("unload",1);panel.SetNum("cmd",0);
    ShowVGUIPanel(c,"info",panel,true);delete panel;
    PrintToChat(c,"[봇거래] 상품창을 열었습니다. 표시되지 않으면 MOTD 설정을 확인하세요.");
    return Plugin_Stop;
}
bool Interact(int c)
{
    if(AimedSlot(c)<0)return false;
    if(GetGameTime()>=nextUse[c]){nextUse[c]=GetGameTime()+1.0;ShowShopMenu(c);}
    return true;
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float vel[3],float angles[3],int &weapon)
{
    if(!Player(c))return Plugin_Continue;
    int old=previous[c];previous[c]=buttons;
    if((buttons&IN_USE)&&!(old&IN_USE)&&Interact(c)){buttons&=~IN_USE;return Plugin_Changed;}
    return Plugin_Continue;
}
public Action Medic(int c,const char[] command,int argc)
{
    if(!Player(c)||argc!=2)return Plugin_Continue;
    char a[8],b[8];GetCmdArg(1,a,sizeof(a));GetCmdArg(2,b,sizeof(b));
    return StrEqual(a,"0")&&StrEqual(b,"0")&&Interact(c)?Plugin_Handled:Plugin_Continue;
}
public Action OnClientSayCommand(int c,const char[] command,const char[] args)
{
    if(!Player(c))return Plugin_Continue;
    char text[64];strcopy(text,sizeof(text),args);TrimString(text);
    if(StrEqual(text,"!관리자입금")||StrEqual(text,"!어드민입금")||StrEqual(text,"!관리자출금")||StrEqual(text,"!어드민출금")){FundsCommand(c,0);return Plugin_Handled;}
    if(StrEqual(text,"봇거래")||StrEqual(text,"!봇거래")||StrEqual(text,"/봇거래")||StrEqual(text,"!상점")){ShowShopMenu(c);return Plugin_Handled;}
    if(StrEqual(text,"!봇거래추가")||StrEqual(text,"!봇거래npc")){if(Root(c))AddCommand(c,0);else PrintToChat(c,"[봇거래] 관리자 전용입니다.");return Plugin_Handled;}
    if(StrEqual(text,"!봇거래제거")||StrEqual(text,"!봇거래삭제")||StrEqual(text,"!상점제거")||StrEqual(text,"!상점삭제")){if(Root(c))RemoveCommand(c,0);else PrintToChat(c,"[봇거래] 관리자 전용입니다.");return Plugin_Handled;}
    return Plugin_Continue;
}
public void OnPluginEnd()
{
    for(int c=1;c<=MaxClients;c++)ShopSession_Revoke(c);
    ending=true;while(menus!=null&&menus.Length)CloseMenu(view_as<Menu>(menus.Get(menus.Length-1)));delete menus;
    for(int i;i<NPC_LIMIT;i++){int e=EntRefToEntIndex(refs[i]);if(e!=INVALID_ENT_REFERENCE)RemoveEntity(e);}
}
