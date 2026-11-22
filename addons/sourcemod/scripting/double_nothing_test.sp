#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#define COUNT 32
#define BASE_HEIGHT 0.0
#define DOUBLE_LIMIT 500000000
#define DON_GAME_POINTS
native int GamePoints_Don(int client,int operation,int value,int round);
int gameRound[COUNT],gameResult[COUNT];
#define ASSET "models/double_nothing_v3/"
#define DISPLAY_ASSET "models/don_screen_v7/"
#define SCREEN_MODEL DISPLAY_ASSET..."screen.mdl"
#define CASH_SOUND "double_nothing_v3/SlotMachineWin.wav"
#define DOWN_SOUND "double_nothing_v3/button_down.wav"
#define UP_SOUND "double_nothing_v3/button_up.wav"
#include "casino_hint.inc"
// Use the shared seat camera; native duck prediction lowers the first-person view.
public Plugin myinfo={name="Double or Nothing Test",author="Codex",description="Seated reconstruction; nonredeemable game points",version="0.4.0"};
enum struct Machine {
    int body;
    int chair;
    int screen;
    int button[5];
    int digit[13];
    int light;
    float chairOrigin[3];
    float origin[3];
    float yaw;
    int user;
    int bet;
    int amount;
    int wins;
    int screenState;
    bool busy;
    bool success;
    bool cashing;
    float due;
    float buttonUp[5];
    float lightUntil;
}
Machine machines[COUNT];
int previous[MAXPLAYERS+1];
bool ready;
char winSounds[8][80],loseSounds[3][80];
char buttonNames[][]={"double","cashout","bet1","bet3","bet5"};
// Cabinet-local positions; v3 sequence compiler rotation is explicitly corrected.
float buttonCenters[5][3]={{-3.635685,-3.351876,58.65285},{-3.532566,3.384284,58.28826},{-8.964149,1.92,55.87086},{-8.964147,0.0,55.87086},{-8.964146,-1.92,55.87086}};
bool Player(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&IsPlayerAlive(c);}
int Entity(int ref){int e=EntRefToEntIndex(ref);return e>MaxClients&&IsValidEntity(e)?e:-1;}
int DoubleResult(int amount,bool success){return success&&amount>0&&amount<=DOUBLE_LIMIT?amount*2:0;}
int WinPitch(int wins){return wins>20?200:wins>8?RoundToNearest(100.0+100.0*float(wins-7)/13.0):100;}
int LossIndex(int wins){return wins>5?2:wins>3?1:0;}
float StreakOffset(int wins){return wins>=10?-0.040:-0.095;}
#include "double_nothing_seats.inc"
#include "double_nothing_setup.inc"

public void OnPluginStart(){
    if(GamePoints_Don(0,0,0,0)<0)SetFailState("Cannot recover game point rounds");
    SeatsInit();DonSetupInit();
    if(FloatAbs((0.815+StreakOffset(2))-(0.760+StreakOffset(21)))>0.0001)SetFailState("DON streak alignment test failed");
    for(int bet=1;bet<=5;bet+=2){int amount=bet;for(int win=1;win<=4;win++){amount=DoubleResult(amount,true);if(amount!=bet*(1<<win))SetFailState("DON bet sequence self-test failed");}}
    RegAdminCmd("sm_doublenothing_remove",RemoveAim,ADMFLAG_GENERIC);
    RegAdminCmd("sm_doublenothing_status",Status,ADMFLAG_GENERIC);
    RegAdminCmd("sm_doublenothing_verify",Verify,ADMFLAG_ROOT);
    AddCommandListener(Chat,"say");AddCommandListener(Chat,"say_team");AddCommandListener(Voice,"voicemenu");
    for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c))OnClientPutInServer(c);
    if(DoubleResult(5,true)!=10||DoubleResult(10,false)!=0||DoubleResult(DOUBLE_LIMIT,true)!=1000000000||DoubleResult(DOUBLE_LIMIT+1,true)!=0
      ||WinPitch(8)!=100||WinPitch(9)!=115||WinPitch(20)!=200||WinPitch(30)!=200||LossIndex(3)!=0||LossIndex(4)!=1||LossIndex(6)!=2)SetFailState("DON arithmetic self-test failed");
}
bool Manifest(const char[] name,bool seatsOnly=false){
    char path[PLATFORM_MAX_PATH],line[PLATFORM_MAX_PATH];BuildPath(Path_SM,path,sizeof(path),"configs/%s",name);
    File f=OpenFile(path,"r");if(f==null){LogError("Missing manifest %s",name);return false;}
    bool ok=true;
    while(f.ReadLine(line,sizeof(line))){
        TrimString(line);if(!line[0])continue;
        if(seatsOnly&&StrContains(line,"casino_seats")==-1)continue;
        if(!FileExists(line,true)){LogError("Missing DON dependency: %s",line);ok=false;}else AddFileToDownloadsTable(line);
    }
    delete f;return ok;
}
public void OnMapStart(){
    CasinoHintReset();
    ready=false;
    for(int i=0;i<COUNT;i++){Machine empty;machines[i]=empty;}
    if(!Manifest("double_nothing_downloads.txt")||!Manifest("tower_slots_downloads.txt",true))return;
    char model[PLATFORM_MAX_PATH];
    if(!PrecacheModel(ASSET..."cabinet.mdl",true)||!PrecacheModel(SCREEN_MODEL,true))return;
    for(int i=0;i<5;i++){Format(model,sizeof(model),"%s%s.mdl",ASSET,buttonNames[i]);if(!PrecacheModel(model,true))return;}
    for(int i=0;i<13;i++){DigitModel(i,model,sizeof(model));if(!PrecacheModel(model,true))return;}
    for(int i=0;i<8;i++){Format(winSounds[i],sizeof(winSounds[]),"double_nothing_v3/DONWin%02d.wav",i+1);if(!PrecacheSound(winSounds[i],true))return;}
    for(int i=0;i<3;i++){Format(loseSounds[i],sizeof(loseSounds[]),"double_nothing_v3/DONLose%02d.wav",i+1);if(!PrecacheSound(loseSounds[i],true))return;}
    if(!PrecacheSound(CASH_SOUND,true)||!PrecacheSound(DOWN_SOUND,true)||!PrecacheSound(UP_SOUND,true))return;
    ready=SeatsPrecache();
}
public void OnClientPutInServer(int c){selectedMachine[c]=0;installCount[c]=0;installSpacing[c]=32.0;inputMode[c]=0;testOutcome[c]=0;SDKHook(c,SDKHook_OnTakeDamage,SeatDamage);}
public Action SeatDamage(int victim,int &attacker,int &inflictor,float &damage,int &damageType){if(!seatSlot[victim])return Plugin_Continue;damage=0.0;return Plugin_Handled;}
public void OnClientDisconnect(int c){seatDiscard[c]=true;SeatStop(c,false);previous[c]=0;inputMode[c]=0;testOutcome[c]=0;installCount[c]=0;}
void Drop(int &ref){int e=Entity(ref);ref=INVALID_ENT_REFERENCE;if(e!=-1)RemoveEntity(e);}
void RemoveMachine(int s){
    for(int c=1;c<=MaxClients;c++)if(seatSlot[c]==s+1)SeatStop(c,false);
    Drop(machines[s].body);Drop(machines[s].chair);Drop(machines[s].screen);Drop(machines[s].light);
    for(int i=0;i<5;i++)Drop(machines[s].button[i]);
    for(int i=0;i<13;i++)Drop(machines[s].digit[i]);
    Machine empty;machines[s]=empty;
}
public void OnPluginEnd(){DonMenusShutdown();ready=false;for(int s=0;s<COUNT;s++)RemoveMachine(s);}
public void OnMapEnd(){ready=false;for(int s=0;s<COUNT;s++)RemoveMachine(s);}
void Release(int s){gameRound[s]=0;machines[s].user=machines[s].amount=machines[s].wins=0;machines[s].busy=false;machines[s].cashing=false;machines[s].screenState=0;UpdateDisplay(s);}
int Prop(const char[] model,bool solid=false){
    int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return INVALID_ENT_REFERENCE;
    DispatchKeyValue(e,"model",model);DispatchKeyValue(e,"solid",solid?"6":"0");
    if(!DispatchSpawn(e)){RemoveEntity(e);return INVALID_ENT_REFERENCE;}
    SetEntProp(e,Prop_Data,"m_takedamage",0);return EntIndexToEntRef(e);
}
void Animate(int ref,const char[] seq){int e=Entity(ref);if(e==-1)return;SetVariantString(seq);AcceptEntityInput(e,"SetAnimation");SetEntPropFloat(e,Prop_Send,"m_flCycle",0.0);SetEntPropFloat(e,Prop_Send,"m_flPlaybackRate",1.0);}
public bool TraceWorld(int e,int mask,any data){return e==0;}
void WorldPoint(int s,float x,float y,float z,float p[3]){
    float a=DegToRad(machines[s].yaw);p[0]=machines[s].origin[0]+Cosine(a)*x-Sine(a)*y;p[1]=machines[s].origin[1]+Sine(a)*x+Cosine(a)*y;p[2]=machines[s].origin[2]+z;
}
void PlacePart(int s,int ref){int e=Entity(ref);if(e==-1)return;float a[3];a[1]=machines[s].yaw+180.0;TeleportEntity(e,machines[s].origin,a,NULL_VECTOR);}
void DigitModel(int i,char[] path,int size){if(i<10)Format(path,size,"%samount%d.mdl",DISPLAY_ASSET,i);else if(i<12)Format(path,size,"%swins%d.mdl",DISPLAY_ASSET,i-10);else Format(path,size,"%scredit.mdl",DISPLAY_ASSET);}
void Skin(int ref,int skin){int e=Entity(ref);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",skin);}
void UpdateDisplay(int s){
    int state=machines[s].screenState;
    Skin(machines[s].screen,state==0&&machines[s].bet>1?4+(machines[s].bet-1)/2:state);
    int n=machines[s].amount;
    int length=1;for(int value=n;value>=10;value/=10)length++;
    float offset=-float(10-length)*0.085/2.0,a=DegToRad(machines[s].yaw+180.0),p[3];
    p=machines[s].origin;
    p[0]+=offset*(Cosine(a)*0.0000198101-Sine(a)*-21.2530468);
    p[1]+=offset*(Sine(a)*0.0000198101+Cosine(a)*-21.2530468);
    p[2]+=offset*-0.10448234;
    for(int i=0;i<10;i++){int e=Entity(machines[s].digit[i]);if(e!=-1)TeleportEntity(e,p,NULL_VECTOR,NULL_VECTOR);}
    for(int i=9;i>=0;i--){Skin(machines[s].digit[i],n>0||i==9?n%10:10);n/=10;}
    // Keep the first visible streak digit beside x, without a blank tens column.
    float du=StreakOffset(machines[s].wins),dv=-0.034;
    float dx=du*0.0000198101+dv*-1.41956236,dy=du*-21.2530468+dv*0.06296401;
    p=machines[s].origin;p[0]+=Cosine(a)*dx-Sine(a)*dy;p[1]+=Sine(a)*dx+Cosine(a)*dy;p[2]+=du*-0.10448234+dv*-12.807956;
    for(int i=10;i<12;i++){int e=Entity(machines[s].digit[i]);if(e!=-1)TeleportEntity(e,p,NULL_VECTOR,NULL_VECTOR);}
    Skin(machines[s].digit[10],state==2&&machines[s].wins>=10?(machines[s].wins/10)%10:10);Skin(machines[s].digit[11],state==2?machines[s].wins%10:10);Skin(machines[s].digit[12],10);
    Skin(machines[s].button[0],!machines[s].busy&&machines[s].amount<=DOUBLE_LIMIT?1:0);
    Skin(machines[s].button[1],!machines[s].busy&&machines[s].amount>0?1:0);
    for(int i=2;i<5;i++)Skin(machines[s].button[i],machines[s].bet==1+(i-2)*2?1:0);
}
bool CreateParts(int s,bool chair=true){
    machines[s].body=Prop(ASSET..."cabinet.mdl",true);machines[s].screen=Prop(SCREEN_MODEL);PlacePart(s,machines[s].body);PlacePart(s,machines[s].screen);
    if(Entity(machines[s].body)==-1||Entity(machines[s].screen)==-1)return false;
    char path[PLATFORM_MAX_PATH];
    for(int i=0;i<5;i++){Format(path,sizeof(path),"%s%s.mdl",ASSET,buttonNames[i]);machines[s].button[i]=Prop(path);if(Entity(machines[s].button[i])==-1)return false;PlacePart(s,machines[s].button[i]);}
    for(int i=0;i<13;i++){DigitModel(i,path,sizeof(path));machines[s].digit[i]=Prop(path);if(Entity(machines[s].digit[i])==-1)return false;PlacePart(s,machines[s].digit[i]);}
    int light=CreateEntityByName("light_dynamic");
    if(light==-1)return false;
    DispatchKeyValue(light,"_light","180 0 255 255");DispatchKeyValue(light,"brightness","2");DispatchKeyValue(light,"distance","100");DispatchKeyValue(light,"style","0");
    if(!DispatchSpawn(light)){RemoveEntity(light);return false;}
    machines[s].light=EntIndexToEntRef(light);float p[3];WorldPoint(s,25.0,0.0,75.0,p);TeleportEntity(light,p,NULL_VECTOR,NULL_VECTOR);AcceptEntityInput(light,"TurnOff");
    machines[s].bet=1;UpdateDisplay(s);
    return !chair||CreateChair(s);
}
void LightResult(int s,bool cash){int e=Entity(machines[s].light);if(e==-1)return;SetVariantString(cash?"255 254 0 255":"179 0 255 255");AcceptEntityInput(e,"Color");AcceptEntityInput(e,"TurnOn");machines[s].lightUntil=GetGameTime()+1.0;}
public bool AimTrace(int e,int mask,any c){return e==0||e>MaxClients;}
int Aim(int c){
    float eye[3],a[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,a);
    Handle tr=TR_TraceRayFilterEx(eye,a,MASK_SOLID,RayType_Infinite,AimTrace,c);int e=TR_DidHit(tr)?TR_GetEntityIndex(tr):-1;float p[3];TR_GetEndPosition(p,tr);delete tr;
    if(GetVectorDistance(eye,p)>200.0)return -1;
    for(int s=0;s<COUNT;s++)if(e>MaxClients&&(Entity(machines[s].body)==e||Entity(machines[s].chair)==e))return s;return -1;
}
public bool ControlTrace(int e,int mask,any s){
    if(e>0&&e<=MaxClients)return false;
    if(e==Entity(machines[s].body)||e==Entity(machines[s].chair)||e==Entity(machines[s].screen))return false;
    for(int i=0;i<5;i++)if(e==Entity(machines[s].button[i]))return false;
    for(int i=0;i<13;i++)if(e==Entity(machines[s].digit[i]))return false;
    return true;
}
int AimButton(int c,int s){
    float eye[3],a[3],dir[3];SeatAim(c,eye,a);GetAngleVectors(a,dir,NULL_VECTOR,NULL_VECTOR);
    float best=9999.0;int hit=-1;
    for(int i=0;i<5;i++){
        float p[3],delta[3];WorldPoint(s,-buttonCenters[i][0],-buttonCenters[i][1],buttonCenters[i][2],p);
        SubtractVectors(p,eye,delta);float along=GetVectorDotProduct(delta,dir);if(along<=0.0||along>150.0)continue;
        float dist=GetVectorDotProduct(delta,delta)-along*along,radius=i<2?2.3:0.9;
        if(dist>radius*radius||dist>=best)continue;
        Handle tr=TR_TraceRayFilterEx(eye,p,MASK_SOLID,RayType_EndPoint,ControlTrace,s);bool blocked=TR_DidHit(tr);delete tr;if(blocked)continue;
        best=dist;hit=i;
    }
    return hit;
}
bool Use(int c){if(!Player(c)||!ready)return false;if(!seatSlot[c])return SeatUse(c);int s=seatSlot[c]-1,b=AimButton(c,s);if(b>=0)Press(c,s,b);return true;}
void Press(int c,int s,int b){
    if(!ready||!Player(c)||seatSlot[c]!=s+1||machines[s].user!=GetClientUserId(c)||machines[s].busy||GetGameTime()<machines[s].due)return;
    if((b==0&&machines[s].amount>DOUBLE_LIMIT)||(b==1&&!machines[s].amount)||(b>=2&&machines[s].amount))return;
    if(b==0&&!machines[s].amount){
        int round=GamePoints_Don(c,1,machines[s].bet,0);
        if(round<0){CasinoHint(c,"게임 포인트가 부족하거나 장부를 확인할 수 없습니다.");return;}
        gameRound[s]=round;
    }
    if(b==0){
        machines[s].success=DonAdmin(c)&&testOutcome[c]>0?testOutcome[c]==1:GetRandomInt(0,1)==1;testOutcome[c]=0;
        gameResult[s]=GamePoints_Don(c,2,machines[s].success?1:0,gameRound[s]);
        if(gameResult[s]<0){CasinoHint(c,"게임 장부 처리 실패. 결과를 다시 확인하세요.");return;}
    }
    if(b==1&&GamePoints_Don(c,3,0,gameRound[s])<0){CasinoHint(c,"게임 포인트 지급을 확인하지 못했습니다. 다시 시도하세요.");return;}
    if(b<2){Animate(machines[s].button[b],"press");machines[s].buttonUp[b]=GetGameTime()+0.25;}
    EmitSoundToAll(DOWN_SOUND,Entity(machines[s].button[b]));
    if(b>=2){machines[s].bet=1+(b-2)*2;machines[s].screenState=0;machines[s].due=GetGameTime()+0.5;UpdateDisplay(s);return;}
    machines[s].busy=true;machines[s].cashing=b==1;machines[s].due=GetGameTime()+0.5;
    if(b==0){if(!machines[s].amount)machines[s].amount=machines[s].bet;machines[s].screenState=1;}
    else {machines[s].screenState=4;for(int copy=0;copy<2;copy++)EmitSoundToAll(CASH_SOUND,Entity(machines[s].body),SNDCHAN_USER_BASE+3+copy);LightResult(s,true);CasinoHint(c,"[더블] %d 획득! 게임 포인트",machines[s].amount);}
    UpdateDisplay(s);
}
void Finish(int s){
    machines[s].busy=false;
    if(machines[s].cashing){machines[s].cashing=false;machines[s].amount=0;machines[s].wins=0;UpdateDisplay(s);return;}
    machines[s].amount=gameResult[s];char sound[80];int pitch=100;
    if(machines[s].success){machines[s].wins++;int level=machines[s].wins-1;if(level>7)level=7;strcopy(sound,sizeof(sound),winSounds[level]);pitch=WinPitch(machines[s].wins);machines[s].screenState=2;LightResult(s,false);}
    else {strcopy(sound,sizeof(sound),loseSounds[LossIndex(machines[s].wins)]);machines[s].wins=0;machines[s].screenState=3;}
    UpdateDisplay(s);for(int copy=0;copy<3;copy++)EmitSoundToAll(sound,Entity(machines[s].body),SNDCHAN_USER_BASE+copy,SNDLEVEL_NORMAL,SND_NOFLAGS,1.0,pitch);
    LogMessage("DON result slot=%d userid=%d win=%d amount=%d",s,machines[s].user,machines[s].success,machines[s].amount);
}
public void OnGameFrame(){
    CasinoHintFrame();
    if(!ready)return;SeatsFrame();float now=GetGameTime();
    for(int s=0;s<COUNT;s++)if(Entity(machines[s].body)!=-1){
        for(int b=0;b<5;b++)if(machines[s].buttonUp[b]>0.0&&now>=machines[s].buttonUp[b]){machines[s].buttonUp[b]=0.0;Animate(machines[s].button[b],"release");EmitSoundToAll(UP_SOUND,Entity(machines[s].button[b]),SNDCHAN_AUTO,SNDLEVEL_NORMAL,SND_NOFLAGS,1.0,150);}
        if(machines[s].lightUntil>0.0&&now>=machines[s].lightUntil){machines[s].lightUntil=0.0;int e=Entity(machines[s].light);if(e!=-1)AcceptEntityInput(e,"TurnOff");}
        if(machines[s].busy&&now>=machines[s].due)Finish(s);
    }
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float vel[3],float angles[3],int &weapon){
    int old=previous[c];previous[c]=buttons;bool use=(buttons&IN_USE)&&!(old&IN_USE);
    if(seatSlot[c]){
        if((buttons&IN_DUCK)&&!(old&IN_DUCK)){SeatStop(c,true);if(!seatSlot[c])return Plugin_Changed;}
        if((buttons&IN_ATTACK3)&&!(old&IN_ATTACK3))seatThird[c]=!seatThird[c];
        if(use||((buttons&IN_ATTACK)&&!(old&IN_ATTACK)))Use(c);
        if((buttons&IN_JUMP)&&!(old&IN_JUMP))Press(c,seatSlot[c]-1,0);
        buttons&=~(IN_ATTACK|IN_ATTACK2|IN_ATTACK3|IN_JUMP|IN_DUCK|IN_USE|IN_RELOAD|IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT);buttons|=IN_DUCK;SeatPhysicsHold(c);
        vel[0]=vel[1]=vel[2]=0.0;weapon=0;return Plugin_Changed;
    }
    if(use&&Use(c)){buttons&=~IN_USE;return Plugin_Changed;}return Plugin_Continue;
}
public Action Voice(int c,const char[] command,int argc){char a[8],b[8];GetCmdArg(1,a,sizeof(a));GetCmdArg(2,b,sizeof(b));return StrEqual(a,"0")&&StrEqual(b,"0")&&Use(c)?Plugin_Handled:Plugin_Continue;}
public Action Chat(int c,const char[] command,int argc){
    char text[80];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);
    if(!StrEqual(text,"!더블삭제"))return Plugin_Continue;
    if(DonAdmin(c))RemoveAim(c,0);return Plugin_Handled;
}
public Action RemoveAim(int c,int args){if(Player(c)){int s=Aim(c);if(s>=0){RemoveMachine(s);ReplyToCommand(c,"[더블] 삭제 완료.");}}return Plugin_Handled;}
public Action Status(int c,int args){int count,seats;for(int s=0;s<COUNT;s++)if(Entity(machines[s].body)!=-1)count++;for(int p=1;p<=MaxClients;p++)if(seatSlot[p])seats++;ReplyToCommand(c,"Double or Nothing 0.4.0 ready=%d machines=%d seated=%d game_points=enabled item_exchange=disabled",ready,count,seats);return Plugin_Handled;}
public Action Verify(int c,int args){
    if(!ready||GetEntityCount()>GetMaxEntities()-100){ReplyToCommand(c,"DON verify FAIL not ready/capacity");return Plugin_Handled;}
    int s=-1;for(int i=0;i<COUNT;i++)if(Entity(machines[i].body)==-1){s=i;break;}if(s==-1)return Plugin_Handled;
    machines[s].origin[2]=-16000.0;
    bool ok=CreateParts(s,false);
    if(ok){for(int state=0;state<5;state++){machines[s].screenState=state;machines[s].amount=1234567890;machines[s].wins=21;UpdateDisplay(s);if(GetEntProp(Entity(machines[s].screen),Prop_Send,"m_nSkin")!=state)ok=false;}
        for(int b=0;b<2;b++){Animate(machines[s].button[b],"press");Animate(machines[s].button[b],"release");}
        int amounts[]={0,2,4,8,16,10,20,40,80,2147483646};
        for(int test=0;test<sizeof(amounts);test++){
            machines[s].amount=amounts[test];machines[s].screenState=2;machines[s].wins=21;UpdateDisplay(s);
            int value=amounts[test];
            for(int i=9;i>=0;i--){if(GetEntProp(Entity(machines[s].digit[i]),Prop_Send,"m_nSkin")!=(value>0||i==9?value%10:10))ok=false;value/=10;}
            if(GetEntProp(Entity(machines[s].digit[10]),Prop_Send,"m_nSkin")!=2||GetEntProp(Entity(machines[s].digit[11]),Prop_Send,"m_nSkin")!=1)ok=false;
        }
        machines[s].screenState=0;
        for(int bet=1;bet<=5;bet+=2){machines[s].bet=bet;UpdateDisplay(s);if(GetEntProp(Entity(machines[s].screen),Prop_Send,"m_nSkin")!=(bet==1?0:4+(bet-1)/2))ok=false;}
        for(int b=2;b<5;b++)if(GetEntProp(Entity(machines[s].button[b]),Prop_Send,"m_nSequence")!=0)ok=false;
        LightResult(s,false);LightResult(s,true);
    }
    RemoveMachine(s);
    if(!SeatCameraVerify())ok=false;
    ReplyToCommand(c,"DON verify %s: parts creation, five screen states, digit skins, buttons, light, cleanup; live seating untested",ok?"PASS":"FAIL");return Plugin_Handled;
}
