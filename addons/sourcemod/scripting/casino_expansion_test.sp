#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include "casino_hint.inc"
#include "casino_cards_rules.inc"
#include "casino_expansion_rules.inc"
#define GAMES 12
#define COUNT 72
#define BASE_HEIGHT 0.0
#define CABINET_HEIGHT 41.57475584
#define STAND_MODEL "models/tower_casino_stand_v1/stand.mdl"
#define CONTROLS_MODEL "models/tower_casino_controls_v1/controls.mdl"
#define WHEEL_MODEL "models/tower_casino_wheel_v14/wheel.mdl"
#define WHEEL_SCREEN "models/tower_casino_wheel_v16/paytable.mdl"
#define WHEEL_HIGHLIGHT "models/tower_casino_wheel_v14/highlight.mdl"
#define WHEEL_DIGIT "models/tower_slots_v6/jackdigit.mdl"
#define WHEEL_SECONDS 15.0
#define SMALL_CONTROLS "models/tower_casino_wheel_v6/controls.mdl"
#define WHEEL_CONTROLS "models/tower_casino_wheel_v14/controls.mdl"
#define WHEEL_REEL "models/tower_casino_wheel_v14/wheel_reel.mdl"
#define LIMIT 1000000
public Plugin myinfo={name="Casino Expansion Test",author="Codex",description="Seven casino games, local virtual chips, not original AGC odds",version="0.3.0"};
enum struct Machine {
    int chair;
    int user;
    bool busy;
    float chairOrigin[3];
    float origin[3];
    float yaw;
}
Machine machines[COUNT];
enum struct Game {
    int body;
    int stand;
    int controls;
    int wheel;
    int wheelSector;
    float wheelLockedUntil;
    int screen;
    int highlight;
    int label;
    int kind;
    float origin[3];
    float yaw;
    int phase;
    float due;
    int order[80];
    bool called[80];
    int count;
    bool lineWon;
    int horses[8];
    float progress[8];
    int winner;
    int pot;
    int reel[3];
    int symbol[3];
    int digits[8];
}
Game games[GAMES];
enum struct Round {
    int phase;
    bool wheelSpin;
    bool reelStarted;
    int wheelAward;
    int wheelTarget;
    int wheelRound;
    int wheelTotal;
    float wheelStarted;
    int wheelTravel;
    int wheelTicks;
    int stops;
    float nextStop;
    int wager;
    int credit;
    int deck[52];
    int cursor;
    int hand[12];
    int hc;
    int dealer[12];
    int dc;
    int hold;
    int reels[3];
    int bonus;
    int hp;
    int dragon;
    bool picks[80];
    int picked;
    int draw[80];
    int drawn;
    int hits;
    int boards[100];
    int cards;
    int horse;
    int contributed;
    bool linePaid;
    float due;
    char result[256];
}
Round rounds[MAXPLAYERS+1];
int chips[MAXPLAYERS+1],revision[MAXPLAYERS+1],previous[MAXPLAYERS+1];
bool ready,ending;float nextFrame,nextUse[MAXPLAYERS+1];ArrayList menus;
ConVar bingoDelay,raceDuration,slotDelay,wheelPool;
char names[][]={"Grand Quest","Wheel of Money","비디오 포커","비디오 블랙잭","키노","Planet Bingo","Silver Saddles"};
char assets[][]={"models/tower_casino_extra_v1/quest.mdl","models/tower_casino_wheel_v15/body.mdl","models/tower_casino_extra_v1/video.mdl","models/tower_casino_extra_v1/video.mdl","models/tower_casino_extra_v1/keno.mdl","models/tower_casino_extra_v1/bingo.mdl","models/tower_casino_extra_v1/racing.mdl"};
char audio[][]={
    "SlotMachineCrank","SlotStopBeep","QuestSwordHit","GrandQuest_Defend","GrandQuest_Heal","GrandQuest_Magic",
    "GrandQuest_DragonBite","QuestJackpot","WOMSpinTick","WOMSpinBonus","VideoPokerCardFlip","VideoPokerHold",
    "VideoPokerWin","CardShuffle","CardFlip","BlackjackMajorWin","KenoBallDrop01","KenoMinorWin",
    "BingoBlot","Bingo_01","Horse_StartGate","Horse_Win",
    "SlotMachineSpinLoop","SlotThunk","WOMMinorWin","WOMMajorWin","WOMJackpot"
};
char wheelAudio[][]={"crank","stop0","stop1","stop2","tick","bonus","fail","ready0","ready1","ready2","ready3","ready4","minor","major","jackpot","button","coins","jackpot_coins"};
#define CARD_SEATS_IGNORE_MOUNT_CLEARANCE
#include "double_nothing_seats.inc"
bool Player(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&IsPlayerAlive(c);}
bool Admin(int c){return Player(c)&&CheckCommandAccess(c,"sm_casinoextra",ADMFLAG_GENERIC);}
int Entity(int ref){int e=EntRefToEntIndex(ref);return e>MaxClients&&IsValidEntity(e)?e:-1;}
int Prop(const char[] model,bool solid=false){int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return 0;DispatchKeyValue(e,"model",model);DispatchKeyValue(e,"solid",solid?"6":"0");if(!DispatchSpawn(e)){RemoveEntity(e);return 0;}SetEntProp(e,Prop_Data,"m_takedamage",0);return EntIndexToEntRef(e);}
void Animate(int ref,const char[] anim){int e=Entity(ref);if(e!=-1){SetVariantString(anim);AcceptEntityInput(e,"SetAnimation");SetEntPropFloat(e,Prop_Send,"m_flCycle",0.0);SetEntPropFloat(e,Prop_Send,"m_flPlaybackRate",1.0);}}
public bool TraceWorld(int e,int mask,any data){return e==0;}
void WorldPoint(int s,float x,float y,float z,float p[3]){p=machines[s].origin;float a=DegToRad(machines[s].yaw);p[0]+=Cosine(a)*x-Sine(a)*y;p[1]+=Sine(a)*x+Cosine(a)*y;p[2]+=z;}
int GameOf(int c){return seatSlot[c]?(seatSlot[c]-1)/6:-1;}
int Seated(int s){return GetClientOfUserId(machines[s].user);}
void Give(int c,int n){if(c>0&&IsClientInGame(c)){chips[c]+=n;if(chips[c]>LIMIT)chips[c]=LIMIT;}}
void SoundPath(int sound,char[] path,int size){Format(path,size,"%s/%s.wav",(sound==0||sound==1||sound==8||sound==9||sound>=22)?"tower_casino_wheel_v2":"tower_casino_extra_v1",audio[sound]);}
void WheelSoundPath(int sound,char[] path,int size){Format(path,size,"tower_casino_wheel_audio_v4/%s.wav",wheelAudio[sound]);}
void Sound(int g,int sound){
    int e=Entity(games[g].body);if(e==-1)return;char path[128];if(sound<sizeof(audio))SoundPath(sound,path,sizeof(path));
    if(games[g].kind==1){
        if(sound==8||sound==9){int c=Seated(g*6);if(!c||!rounds[c].wheelSpin)return;}
        int cue=-1;
        if(sound==0)cue=0;
        else if(sound==23)cue=GetRandomInt(1,3);
        else if(sound==8)cue=4;
        else if(sound==9){
            // Stop the prior ready cue before announcing the next bonus.
            for(int i=7;i<=11;i++){
                char previousCue[128];WheelSoundPath(i,previousCue,sizeof(previousCue));StopSound(e,SNDCHAN_AUTO,previousCue);
                for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c)StopSound(c,SNDCHAN_AUTO,previousCue);}
            }
            cue=GetRandomInt(7,11);
        }
        else if(sound>=24&&sound<=26){
            // The original cabinet Speaker replaces its previous win cue.
            for(int i=12;i<=14;i++){
                char prior[128];WheelSoundPath(i,prior,sizeof(prior));StopSound(e,SNDCHAN_AUTO,prior);
                for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c)StopSound(c,SNDCHAN_AUTO,prior);}
            }
            cue=sound-12;
        }
        else if(sound>=27&&sound<=30)cue=sound==27?5:(sound==28?6:(sound==29?15:16));
        else if(sound==31)cue=17;
        if(cue>=0)WheelSoundPath(cue,path,sizeof(path));
    }
    if(!path[0])return;
    float pos[3];pos=games[g].origin;pos[2]+=CABINET_HEIGHT+28.8;
    int channel=sound==22?SNDCHAN_STATIC:SNDCHAN_AUTO;
    // Match Diamond's playback gain; preserve the original wheel-loop pitch variation.
    float volume=1.0;
    int pitch=(games[g].kind==1&&sound==22)?GetRandomInt(100,101):SNDPITCH_NORMAL;
    for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c)&&!IsFakeClient(c)){
        if(GameOf(c)==g)EmitSoundToClient(c,path,c,channel,SNDLEVEL_NONE,SND_NOFLAGS,volume,pitch);
        else EmitSoundToClient(c,path,e,channel,SNDLEVEL_NORMAL,SND_NOFLAGS,volume,pitch,-1,pos,NULL_VECTOR,false);
    }
}
void StopWheelAudio(int g,bool motionOnly=false){
    if(games[g].kind!=1)return;
    int e=Entity(games[g].body);char path[128];
    for(int i=0;i<sizeof(wheelAudio);i++){
        if(motionOnly&&(i<4||i>11))continue;
        WheelSoundPath(i,path,sizeof(path));if(e!=-1)StopSound(e,SNDCHAN_AUTO,path);
        for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c)StopSound(c,SNDCHAN_AUTO,path);}
    }
}
void StopSpin(int g){
    char path[128];SoundPath(22,path,sizeof(path));int e=Entity(games[g].body);if(e!=-1)StopSound(e,SNDCHAN_STATIC,path);
    for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c)StopSound(c,SNDCHAN_STATIC,path);}
}
void BetDisplay(int g,int credit){
    if(g<0||games[g].kind>1)return;int skin=credit==5?2:(credit==3?1:0);
    int e=Entity(games[g].controls);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",skin+1);
    e=Entity(games[g].highlight);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",skin);
}
void SelectBet(int c,int credit){
    int g=GameOf(c);if(g<0||games[g].kind>1||rounds[c].phase||rounds[c].bonus)return;
    if(GetGameTime()<games[g].wheelLockedUntil)return;
    if(credit!=1&&credit!=3&&credit!=5)return;
    rounds[c].credit=credit;BetDisplay(g,credit);
    char sequence[16];Format(sequence,sizeof(sequence),"press%d",credit);Animate(games[g].controls,sequence);
    if(games[g].kind==1)Sound(g,29);else EmitSoundToClient(c,"double_nothing_v3/button_down.wav",c,SNDCHAN_AUTO,SNDLEVEL_NONE);
}
void Release(int s){int c=Seated(s);StopSpin(s/6);StopWheelAudio(s/6);WheelDisplay(s/6,false);machines[s].user=0;if(c){Round blank;rounds[c]=blank;rounds[c].credit=1;rounds[c].horse=0;revision[c]++;}}
void UpdateDisplay(int s){int c=Seated(s);if(c){CasinoHint(c,"E/메딕: 메뉴 · Ctrl: 하차 · 휠: 시점\n가상 칩 시험 · 원본 확률 아님");Show(c);}}
void EndMenu(Menu m){if(menus==null)return;int i=menus.FindValue(m);if(i<0)return;menus.Erase(i);m.Cancel();delete m;}
Menu NewMenu(MenuHandler handler){Menu m=new Menu(handler);menus.Push(m);return m;}
#include "casino_expansion_setup.inc"
public void OnPluginStart(){
    ExpansionRulesTest();menus=new ArrayList();SeatsInit();
    AddCommandListener(ExtraChat,"say");AddCommandListener(ExtraChat,"say_team");
    RegAdminCmd("sm_casinoextra",Setup,ADMFLAG_GENERIC);RegAdminCmd("sm_casinoextra_selftest",SelfTest,ADMFLAG_ROOT);
    RegConsoleCmd("sm_casinoplay",Open);AddCommandListener(Medic,"voicemenu");
    bingoDelay=CreateConVar("sm_casinoextra_bingo_call","7.0","Seconds between bingo calls",_,true,0.5,true,30.0);
    raceDuration=CreateConVar("sm_casinoextra_race_seconds","60.0","Local test race duration",_,true,5.0,true,120.0);
    slotDelay=CreateConVar("sm_casinoextra_spin_seconds","3.0","Slot reel duration",_,true,1.0,true,10.0);
    wheelPool=CreateConVar("sm_casinoextra_wheel_pool","0","Wheel shared virtual-chip jackpot",FCVAR_DONTRECORD,true,0.0,true,99999999.0);
    AutoExecConfig(true,"casino_expansion_test");
    for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c))OnClientPutInServer(c);
}
public void OnMapStart(){
    ready=false;CasinoHintReset();nextFrame=0.0;for(int g=0;g<GAMES;g++){Game blank;games[g]=blank;}for(int s=0;s<COUNT;s++){Machine blank;machines[s]=blank;}
    char path[PLATFORM_MAX_PATH],line[PLATFORM_MAX_PATH];BuildPath(Path_SM,path,sizeof(path),"configs/casino_expansion_downloads.txt");File f=OpenFile(path,"r");if(f==null){LogError("Expansion manifest missing");return;}
    bool missing;while(f.ReadLine(line,sizeof(line))){TrimString(line);if(!line[0])continue;if(!FileExists(line,true)){LogError("Missing expansion asset %s",line);missing=true;}else AddFileToDownloadsTable(line);}delete f;if(missing)return;
    for(int i=0;i<sizeof(assets);i++)if(!PrecacheModel(assets[i],true))return;
    if(!PrecacheModel("models/tower_casino_extra_v1/horse.mdl",true))return;
    if(!PrecacheModel(STAND_MODEL,true))return;
    if(!PrecacheModel(CONTROLS_MODEL,true))return;
    if(!PrecacheModel(SMALL_CONTROLS,true))return;
    if(!PrecacheModel(WHEEL_CONTROLS,true))return;
    if(!PrecacheModel(WHEEL_MODEL,true)||!PrecacheModel(WHEEL_SCREEN,true))return;
    if(!PrecacheModel(WHEEL_HIGHLIGHT,true))return;
    if(!PrecacheModel("models/tower_casino_extra_v1/quest_reel.mdl",true)||!PrecacheModel(WHEEL_REEL,true))return;
    for(int i=0;i<sizeof(audio);i++){SoundPath(i,path,sizeof(path));if(!PrecacheSound(path,true))return;}
    for(int i=0;i<sizeof(wheelAudio);i++){WheelSoundPath(i,path,sizeof(path));if(!PrecacheSound(path,true))return;}
    if(!PrecacheSound("double_nothing_v3/button_down.wav",true))return;
    if(!PrecacheModel(WHEEL_DIGIT,true))return;
    ready=SeatsPrecache();
}
public void OnClientPutInServer(int c){chips[c]=1000;Round blank;rounds[c]=blank;rounds[c].credit=1;previous[c]=0;nextUse[c]=0.0;SDKHook(c,SDKHook_OnTakeDamage,SeatDamage);}
public Action SeatDamage(int c,int &a,int &inf,float &d,int &type){if(!seatSlot[c])return Plugin_Continue;d=0.0;return Plugin_Handled;}
public void OnClientDisconnect(int c){seatDiscard[c]=true;SeatStop(c,false);chips[c]=0;revision[c]++;extraKind[c]=extraCount[c]=extraInput[c]=extraTest[c]=0;extraSpacing[c]=0.0;}
public void OnMapEnd(){ready=false;for(int g=0;g<GAMES;g++)Remove(g);}
public void OnPluginEnd(){ending=true;while(menus!=null&&menus.Length)EndMenu(view_as<Menu>(menus.Get(menus.Length-1)));delete menus;for(int g=0;g<GAMES;g++)Remove(g);}
void Remove(int g){
    StopSpin(g);
    StopWheelAudio(g);
    for(int i=0;i<8;i++){int digit=Entity(games[g].digits[i]);if(digit!=-1)RemoveEntity(digit);games[g].digits[i]=0;}
    games[g].phase=0;
    int wheel=Entity(games[g].wheel);if(wheel!=-1)RemoveEntity(wheel);games[g].wheel=0;
    int screen=Entity(games[g].screen);if(screen!=-1)RemoveEntity(screen);games[g].screen=0;
    int highlight=Entity(games[g].highlight);if(highlight!=-1)RemoveEntity(highlight);games[g].highlight=0;
    int controls=Entity(games[g].controls);if(controls!=-1)RemoveEntity(controls);games[g].controls=0;
    int stand=Entity(games[g].stand);if(stand!=-1)RemoveEntity(stand);games[g].stand=0;
    for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c){Give(c,rounds[c].wager+rounds[c].contributed);machines[s].busy=false;SeatStop(c,false);}int e=Entity(machines[s].chair);if(e!=-1)RemoveEntity(e);Machine blank;machines[s]=blank;}
    int e=Entity(games[g].body);if(e!=-1)RemoveEntity(e);e=Entity(games[g].label);if(e!=-1)RemoveEntity(e);for(int i=0;i<8;i++){e=Entity(games[g].horses[i]);if(e!=-1)RemoveEntity(e);}for(int i=0;i<3;i++){e=Entity(games[g].reel[i]);if(e!=-1)RemoveEntity(e);}Game blank;games[g]=blank;
}
public Action Setup(int c,int args){
    if(!Admin(c)||ending)return Plugin_Handled;
    int selected=extraKind[c];
    if(args==1){char arg[16];GetCmdArg(1,arg,sizeof(arg));int kind=StringToInt(arg);char valid[16];IntToString(kind,valid,sizeof(valid));if(kind>=0&&kind<7&&StrEqual(arg,valid))selected=kind;}
    extraKind[c]=selected;extraInput[c]=0;ExtraSetup(c);return Plugin_Handled;
}
int CreateGame(int c,int kind,const float p[3],float yaw){
    if(!ready||!Admin(c)||kind<0||kind>=7||seatSlot[c])return -1;
    int g=-1;for(int i=0;i<GAMES;i++)if(Entity(games[i].body)==-1){g=i;break;}if(g<0||GetEntityCount()>GetMaxEntities()-160){PrintToChat(c,"[카지노] 설치 한도입니다.");return -1;}
    float angle[3];
    games[g].kind=kind;games[g].origin=p;games[g].yaw=yaw;games[g].body=Prop(assets[kind],true);
    // Match tower_slots: studiomdl adds +90 degrees; keep logical seat/offset yaw unchanged.
    int e=Entity(games[g].body);if(e==-1){Remove(g);return -1;}angle[0]=angle[2]=0.0;angle[1]=games[g].yaw-90.0;TeleportEntity(e,p,angle,NULL_VECTOR);
    if(kind<=4){
        float raised[3];raised=p;raised[2]+=CABINET_HEIGHT;TeleportEntity(e,raised,angle,NULL_VECTOR);
        games[g].stand=Prop(STAND_MODEL,true);int stand=Entity(games[g].stand);
        if(stand==-1){Remove(g);return -1;}TeleportEntity(stand,p,angle,NULL_VECTOR);
        games[g].controls=Prop(kind==1?WHEEL_CONTROLS:(kind<=1?SMALL_CONTROLS:CONTROLS_MODEL));int control=Entity(games[g].controls);
        if(control==-1){Remove(g);return -1;}TeleportEntity(control,raised,angle,NULL_VECTOR);Animate(games[g].controls,"idle");
    }
    int seats=kind>=5?6:1;
    for(int i=0;i<seats;i++){
        int s=g*6+i;machines[s].origin=p;machines[s].yaw=games[g].yaw;
        if(seats>1){float r=DegToRad(games[g].yaw+float(i)*60.0);machines[s].origin[0]+=Cosine(r)*110.0;machines[s].origin[1]+=Sine(r)*110.0;machines[s].yaw=games[g].yaw+float(i)*60.0;}
        if(!CreateChair(s)){Remove(g);PrintToChat(c,"[카지노] 의자 바닥이 없어 설치 취소.");return -1;}
    }
    if(kind<=1)for(int i=0;i<3;i++){
        games[g].reel[i]=Prop(kind==0?"models/tower_casino_extra_v1/quest_reel.mdl":WHEEL_REEL);e=Entity(games[g].reel[i]);if(e==-1){Remove(g);return -1;}
        // Measured small-body windows: centers Y=-9.0555,-5.142,-1.2345, Z=29.376; reel mesh spans local Y=0..3.2.
        float centers[3]={-9.0555,-5.142,-1.2345};
        float point[3];
        if(kind==1){
            // Original window positions leave room for the restored two-line LED component.
            float original[3][3]={{-3.02197174,-10.63874268,28.81405273},{-3.02196869,-6.73296448,28.81405273},{-3.02192719,-2.80870026,28.81405273}};
            SetEntPropFloat(e,Prop_Send,"m_flModelScale",1.0);
            WorldPoint(g*6,original[i][0],original[i][1],CABINET_HEIGHT+original[i][2],point);
        }else{
            SetEntPropFloat(e,Prop_Send,"m_flModelScale",0.85);
            WorldPoint(g*6,-1.95,centers[i]-1.36,CABINET_HEIGHT+29.376,point);
        }
        TeleportEntity(e,point,angle,NULL_VECTOR);games[g].symbol[i]=1;HoldReel(g,i);
    }
    if(kind==1){
        games[g].wheel=Prop(WHEEL_MODEL);games[g].screen=Prop(WHEEL_SCREEN);
        games[g].highlight=Prop(WHEEL_HIGHLIGHT);int highlight=Entity(games[g].highlight);
        if(highlight==-1){Remove(g);return -1;}
        int wheel=Entity(games[g].wheel),screen=Entity(games[g].screen);
        if(wheel==-1||screen==-1){Remove(g);return -1;}
        float point[3];WorldPoint(g*6,0.0,0.0,CABINET_HEIGHT+61.304,point);TeleportEntity(wheel,point,angle,NULL_VECTOR);HoldWheel(g);
        WorldPoint(g*6,0.0,0.0,CABINET_HEIGHT,point);TeleportEntity(screen,point,angle,NULL_VECTOR);
        TeleportEntity(highlight,point,angle,NULL_VECTOR);
        for(int i=0;i<8;i++){
            games[g].digits[i]=Prop(WHEEL_DIGIT);int digit=Entity(games[g].digits[i]);
            if(digit==-1){Remove(g);return -1;}
            WorldPoint(g*6,3.78,(float(i)-3.5)*2.05,CABINET_HEIGHT+47.525,point);
            TeleportEntity(digit,point,angle,NULL_VECTOR);
        }
        WheelCounters();
    }
    if(kind==6)for(int i=0;i<8;i++){games[g].horses[i]=Prop("models/tower_casino_extra_v1/horse.mdl");e=Entity(games[g].horses[i]);if(e==-1){Remove(g);return -1;}float at[3];at=p;at[0]+=65.0+float(i)*2.0;at[2]+=24.0;TeleportEntity(e,at,angle,NULL_VECTOR);SetEntPropFloat(e,Prop_Send,"m_flModelScale",0.4);}
    Label(g,"READY · TEST ODDS / VIRTUAL CHIPS");
    if(kind<=4){int label=Entity(games[g].label);if(label!=-1){float top[3];top=p;top[2]+=90.0+CABINET_HEIGHT;TeleportEntity(label,top,NULL_VECTOR,NULL_VECTOR);}}
    PrintToChat(c,"[카지노] %s 설치. 의자를 보고 E/메딕으로 착석.",names[kind]);
    return g;
}
void WheelCounters(){
    for(int g=0;g<GAMES;g++)if(games[g].kind==1){
        int value=wheelPool.IntValue;
        for(int i=7;i>=0;i--){int skin=(value>0||i==7)?value%10:10;value/=10;int e=Entity(games[g].digits[i]);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",skin);}
    }
}
void WheelDisplay(int g,bool active){
    if(g<0||g>=GAMES||games[g].kind!=1)return;
    int body=Entity(games[g].body);if(body!=-1)SetEntProp(body,Prop_Send,"m_nSkin",active?1:0);
}
void Label(int g,const char[] text){
    if(games[g].kind==1){int c=Seated(g*6);WheelDisplay(g,c>0&&(rounds[c].bonus>0||rounds[c].wheelSpin));return;}
    int e=Entity(games[g].label);if(e==-1){e=CreateEntityByName("point_worldtext");if(e==-1)return;DispatchKeyValue(e,"textsize","3");DispatchKeyValue(e,"orientation","1");DispatchKeyValue(e,"color","255 220 100 255");DispatchKeyValue(e,"message",text);if(!DispatchSpawn(e)){RemoveEntity(e);return;}games[g].label=EntIndexToEntRef(e);float p[3];p=games[g].origin;p[2]+=90.0;TeleportEntity(e,p,NULL_VECTOR,NULL_VECTOR);}else{SetVariantString(text);AcceptEntityInput(e,"SetText");}
}
public Action Open(int c,int args){if(Player(c)&&seatSlot[c])Show(c);return Plugin_Handled;}
public Action Medic(int c,const char[] command,int args){if(!ready||!Player(c)||args!=2)return Plugin_Continue;char a[8],b[8];GetCmdArg(1,a,sizeof(a));GetCmdArg(2,b,sizeof(b));if(!StrEqual(a,"0")||!StrEqual(b,"0"))return Plugin_Continue;if(GetGameTime()<nextUse[c])return Plugin_Continue;nextUse[c]=GetGameTime()+0.3;if(seatSlot[c]){if(!ExtraUse(c))Show(c);return Plugin_Handled;}return SeatUse(c)?Plugin_Handled:Plugin_Continue;}
void Item(Menu m,int c,const char[] key,const char[] text,bool enabled=true){char id[64];Format(id,sizeof(id),"%d:%s",revision[c],key);m.AddItem(id,text,enabled?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);}
void CardName(int card,char[] text,int size){char suits[][]={"♠","♥","♦","♣"},ranks[][]={"2","3","4","5","6","7","8","9","10","J","Q","K","A"};Format(text,size,"%s%s",suits[card/13],ranks[card%13]);}
void HandText(const int[] hand,int count,char[] text,int size){text[0]=0;for(int i=0;i<count;i++){char card[16];CardName(hand[i],card,sizeof(card));StrCat(text,size,card);StrCat(text,size," ");}}
void Show(int c){
    if(ending||!Player(c)||!seatSlot[c])return;int g=GameOf(c),kind=games[g].kind;revision[c]++;
    BetDisplay(g,rounds[c].credit);
    if(kind==1){
        if(rounds[c].result[0])CasinoHint(c,"%s\n스페이스: 회전 · E: 버튼/레버\nCtrl: 내리기 · 휠 클릭: 시점",rounds[c].result);
        else CasinoHint(c,"스페이스: 회전 · E: 버튼/레버\nCtrl: 내리기 · 휠 클릭: 시점");
        return;
    }
    Menu m=NewMenu(PlayHandler);char title[1024],label[128],key[16],hand[256];
    Format(title,sizeof(title),"%s · 가상 칩 %d\n원본 서버 확률 아님 · 시험 규칙\n%s",names[kind],chips[c],rounds[c].result);
    if(rounds[c].phase==1){Item(m,c,"refresh","진행 중 · 상태 확인");}
    else if(kind<=1){
        if(rounds[c].bonus>0){
            Format(label,sizeof(label),"보너스 %d회 · 나 %d / 드래곤 %d",rounds[c].bonus,rounds[c].hp,rounds[c].dragon);StrCat(title,sizeof(title),"\n");StrCat(title,sizeof(title),label);
            if(kind==0){Item(m,c,"sword","검 공격");Item(m,c,"defend","방어");Item(m,c,"heal","치유");Item(m,c,"magic","마법");}
        }else{Format(label,sizeof(label),"%d크레딧 스핀",rounds[c].credit);Item(m,c,"play",label,chips[c]>=rounds[c].credit);Item(m,c,"bet1","1 크레딧 베팅");Item(m,c,"bet3","3 크레딧 베팅");Item(m,c,"bet5","5 크레딧 베팅");}
    }else if(kind==2&&rounds[c].phase==2){
        for(int i=0;i<5;i++){CardName(rounds[c].hand[i],hand,sizeof(hand));Format(label,sizeof(label),"%s %s",rounds[c].hold&(1<<i)?"HOLD":"교체",hand);Format(key,sizeof(key),"hold%d",i);Item(m,c,key,label);}Item(m,c,"draw","DRAW · 교체 확정");
    }else if(kind==3&&rounds[c].phase==2){
        HandText(rounds[c].hand,rounds[c].hc,hand,sizeof(hand));Format(label,sizeof(label),"\n내 패 %s = %d",hand,BlackjackValue(rounds[c].hand,rounds[c].hc));StrCat(title,sizeof(title),label);CardName(rounds[c].dealer[0],hand,sizeof(hand));Format(label,sizeof(label),"\n딜러 %s [숨김]",hand);StrCat(title,sizeof(title),label);
        Item(m,c,"hit","히트");Item(m,c,"stand","스탠드");Item(m,c,"double","더블다운",rounds[c].hc==2&&chips[c]>=rounds[c].wager);
    }else if(kind==4){
        Format(label,sizeof(label),"번호 선택 (%d/10)",rounds[c].picked);Item(m,c,"numbers",label);Item(m,c,"quick","10개 자동 선택");Item(m,c,"clear","선택 초기화");Item(m,c,"play","10칩 베팅 · 20번호 추첨",rounds[c].picked>0&&chips[c]>=10);
    }else if(kind==5){
        Format(label,sizeof(label),"카드 구매 10칩 (%d/4)",rounds[c].cards);Item(m,c,"buy",label,games[g].phase<2&&rounds[c].cards<4&&chips[c]>=10);
        Item(m,c,"board","내 빙고 카드 보기");Item(m,c,"refresh","호출/결과 확인");
    }else if(kind==6){
        Format(label,sizeof(label),"선택한 말: %d번 (동일 확률 · 8배 반환)",rounds[c].horse+1);Item(m,c,"horse",label,games[g].phase<2&&rounds[c].contributed==0);
        Item(m,c,"buy","10칩 베팅",games[g].phase<2&&rounds[c].contributed==0&&chips[c]>=10);Item(m,c,"refresh","레이스 현황");
    }else{Format(label,sizeof(label),kind==2?"%d크레딧 카드 받기":"%d크레딧 블랙잭 (S17 / 3:2)",rounds[c].credit);Item(m,c,"play",label,chips[c]>=rounds[c].credit);Item(m,c,"bet","베팅 1 → 3 → 5 변경");}
    Item(m,c,"refill","시험 칩 1000 충전",chips[c]==0&&rounds[c].phase==0&&rounds[c].contributed==0&&rounds[c].bonus==0);
    Item(m,c,"leave","일어나기 (참가 중 베팅은 포기)");m.SetTitle("%s",title);m.Display(c,MENU_TIME_FOREVER);
}
public int PlayHandler(Menu m,MenuAction a,int c,int item){
    if(a==MenuAction_End){EndMenu(m);return 0;}if(ending||a!=MenuAction_Select||!Player(c)||!seatSlot[c])return 0;
    char key[64],part[2][32];m.GetItem(item,key,sizeof(key));if(ExplodeString(key,":",part,2,32)!=2||StringToInt(part[0])!=revision[c]){Show(c);return 0;}revision[c]++;
    int g=GameOf(c),kind=games[g].kind;
    if(StrEqual(part[1],"leave")){SeatStop(c,true);return 0;}
    if(rounds[c].phase==1){Show(c);return 0;}
    if(StrEqual(part[1],"refill")){if(chips[c]==0&&rounds[c].phase==0&&rounds[c].contributed==0&&rounds[c].bonus==0)chips[c]=1000;}
    else if(StrEqual(part[1],"bet")&&rounds[c].phase==0&&rounds[c].bonus==0)rounds[c].credit=rounds[c].credit==1?3:(rounds[c].credit==3?5:1);
    else if((StrEqual(part[1],"bet1")||StrEqual(part[1],"bet3")||StrEqual(part[1],"bet5"))&&kind<=1&&rounds[c].phase==0&&rounds[c].bonus==0)SelectBet(c,part[1][3]-'0');
    else if(StrEqual(part[1],"play")&&rounds[c].phase==0&&rounds[c].bonus==0)Start(c);
    else if(kind<=1&&rounds[c].bonus>0)Bonus(c,part[1]);
    else if(kind==2&&rounds[c].phase==2){
        if(StrContains(part[1],"hold")==0&&part[1][4]>='0'&&part[1][4]<='4'&&part[1][5]==0){rounds[c].hold^=1<<(part[1][4]-'0');Sound(g,11);}
        else if(StrEqual(part[1],"draw"))DrawPoker(c);
    }else if(kind==3&&rounds[c].phase==2){
        if(StrEqual(part[1],"hit")||StrEqual(part[1],"double")){
            bool twice=StrEqual(part[1],"double");if(twice&&(rounds[c].hc!=2||chips[c]<rounds[c].wager)){Show(c);return 0;}
            if(twice){chips[c]-=rounds[c].wager;rounds[c].wager*=2;}
            if(rounds[c].hc<12)rounds[c].hand[rounds[c].hc++]=rounds[c].deck[rounds[c].cursor++];Sound(g,14);rounds[c].due=GetGameTime()+30.0;
            if(twice||rounds[c].hc==12||BlackjackValue(rounds[c].hand,rounds[c].hc)>=21)FinishBJ(c);
        }else if(StrEqual(part[1],"stand"))FinishBJ(c);
    }else if(kind==4){
        if(StrEqual(part[1],"numbers")){Numbers(c,0);return 0;}
        if(StrEqual(part[1],"clear")||StrEqual(part[1],"quick")){for(int i=0;i<80;i++)rounds[c].picks[i]=false;rounds[c].picked=0;if(StrEqual(part[1],"quick")){int pool[80];CasinoShuffle(pool,80);for(int i=0;i<10;i++)rounds[c].picks[pool[i]]=true;rounds[c].picked=10;}}
    }else if(kind>=5){
        if(StrEqual(part[1],"horse")&&kind==6&&games[g].phase<2&&rounds[c].contributed==0)rounds[c].horse=(rounds[c].horse+1)%8;
        else if(StrEqual(part[1],"buy"))Buy(c);
        else if(StrEqual(part[1],"board")&&kind==5){Board(c);return 0;}
    }
    if(seatSlot[c])Show(c);return 0;
}
void Numbers(int c,int start){
    revision[c]++;Menu m=NewMenu(NumberHandler);m.SetTitle("키노 번호 1~80 · 최대 10개 (%d 선택)",rounds[c].picked);
    for(int i=0;i<80;i++){char key[32],label[32];Format(key,sizeof(key),"%d:%d",revision[c],i);Format(label,sizeof(label),"%s%d",rounds[c].picks[i]?"✓ ":"",i+1);m.AddItem(key,label);}m.ExitBackButton=true;m.DisplayAt(c,start,MENU_TIME_FOREVER);
}
public int NumberHandler(Menu m,MenuAction a,int c,int item){
    if(a==MenuAction_End){EndMenu(m);return 0;}if(ending||!Player(c)||!seatSlot[c]||games[GameOf(c)].kind!=4||rounds[c].phase)return 0;
    if(a==MenuAction_Cancel&&item==MenuCancel_ExitBack){Show(c);return 0;}if(a!=MenuAction_Select)return 0;
    char key[32],p[2][16];m.GetItem(item,key,sizeof(key));if(ExplodeString(key,":",p,2,16)!=2||StringToInt(p[0])!=revision[c])return 0;int n=StringToInt(p[1]);if(n<0||n>=80)return 0;
    if(rounds[c].picks[n]){rounds[c].picks[n]=false;rounds[c].picked--;}else if(rounds[c].picked<10){rounds[c].picks[n]=true;rounds[c].picked++;}Numbers(c,(item/7)*7);return 0;
}
void Start(int c){
    if(ending||!ready||!Player(c)||!seatSlot[c]||rounds[c].phase)return;
    if(GetGameTime()<games[GameOf(c)].wheelLockedUntil){CasinoHint(c,"잭팟 연출 중 · %.0f초 후 조작 가능",games[GameOf(c)].wheelLockedUntil-GetGameTime());return;}
    if(rounds[c].bonus>0){if(games[GameOf(c)].kind==1)StartWheel(c);return;}
    int g=GameOf(c),kind=games[g].kind,cost=kind==4?10:rounds[c].credit;if(kind>4||chips[c]<cost||(kind==4&&rounds[c].picked==0))return;
    chips[c]-=cost;rounds[c].wager=cost;rounds[c].result[0]=0;
    if(kind<=1){
        rounds[c].wheelRound=0;rounds[c].wheelTotal=0;
        int forced=Admin(c)?extraTest[c]:0;extraTest[c]=0;
        if(kind==1&&!forced){int deposit=(cost+1)/2;wheelPool.IntValue=wheelPool.IntValue>99999999-deposit?99999999:wheelPool.IntValue+deposit;WheelCounters();}
        if(forced)PrintToChat(c,"[카지노 테스트] 관리자 지정 결과를 이번 1회에 적용합니다.");
        Animate(games[g].controls,"leverpull");
        for(int i=0;i<3;i++)rounds[c].reels[i]=forced==7?i+1:(forced>0?forced-1:GetRandomInt(0,5));
        rounds[c].phase=1;rounds[c].reelStarted=false;rounds[c].due=GetGameTime()+1.0;rounds[c].stops=0;Sound(g,0);Label(g,"SPINNING...");
    }
    else if(kind==4){CasinoShuffle(rounds[c].draw,80);rounds[c].drawn=rounds[c].hits=0;rounds[c].phase=1;rounds[c].due=GetGameTime()+0.5;}
    else{
        CasinoShuffle(rounds[c].deck,52);rounds[c].cursor=0;rounds[c].hold=0;rounds[c].phase=2;rounds[c].due=GetGameTime()+30.0;rounds[c].hc=kind==2?5:2;
        for(int i=0;i<rounds[c].hc;i++)rounds[c].hand[i]=rounds[c].deck[rounds[c].cursor++];
        if(kind==3){rounds[c].dc=2;for(int i=0;i<2;i++)rounds[c].dealer[i]=rounds[c].deck[rounds[c].cursor++];Sound(g,13);if(BlackjackValue(rounds[c].hand,2)==21||BlackjackValue(rounds[c].dealer,2)==21)FinishBJ(c);}else Sound(g,10);
    }
}
void StartReels(int c,float now){
    int g=GameOf(c);Animate(games[g].controls,"idle");
    for(int i=0;i<3;i++){
        int target=games[g].kind==1?WheelReel(rounds[c].reels[i]):rounds[c].reels[i];
        char sequence[32];Format(sequence,sizeof(sequence),"r_%d_%d_%d",games[g].symbol[i],target,i+1);
        int e=Entity(games[g].reel[i]);if(e!=-1){char idle[24];Format(idle,sizeof(idle),"idle_%d",target);SetVariantString(idle);AcceptEntityInput(e,"SetDefaultAnimation");}
        Animate(games[g].reel[i],sequence);if(e!=-1)SetEntPropFloat(e,Prop_Send,"m_flPlaybackRate",3.0/slotDelay.FloatValue);
        games[g].symbol[i]=target;
    }
    rounds[c].reelStarted=true;rounds[c].due=now+slotDelay.FloatValue;rounds[c].nextStop=now+slotDelay.FloatValue/3.0;Sound(g,22);
}
void HoldReel(int g,int index){
    int e=Entity(games[g].reel[index]);if(e==-1)return;
    char idle[24];Format(idle,sizeof(idle),"idle_%d",games[g].symbol[index]);
    SetVariantString(idle);AcceptEntityInput(e,"SetDefaultAnimation");
    Animate(games[g].reel[index],idle);SetEntPropFloat(e,Prop_Send,"m_flPlaybackRate",0.0);
}
void Result(int c,int award,const char[] text,bool show=true){
    int g=GameOf(c);Give(c,award);Format(rounds[c].result,sizeof(rounds[].result),"%s · 반환 %d (원금 포함)",text,award);rounds[c].phase=0;rounds[c].wager=0;
    if(g>=0&&games[g].kind==1)Format(rounds[c].result,sizeof(rounds[].result),"%d칩 획득",award);
    else PrintToChat(c,"[카지노] %s",rounds[c].result);
    if(g>=0){Label(g,rounds[c].result);if(show)Show(c);}
}
void ResolveSlot(int c){
    StopSpin(GameOf(c));
    int g=GameOf(c),bonus;for(int i=0;i<3;i++)if(rounds[c].reels[i]==0)bonus++;
    for(int i=0;i<3;i++)HoldReel(g,i);
    int symbol=0,matches=bonus;if(rounds[c].reels[0]==rounds[c].reels[1]&&rounds[c].reels[1]==rounds[c].reels[2]){symbol=rounds[c].reels[0];matches=3;}
    int award=SlotPay(symbol,matches,rounds[c].credit);char result[128];Format(result,sizeof(result),"릴 %d | %d | %d",rounds[c].reels[0],rounds[c].reels[1],rounds[c].reels[2]);
    if(games[g].kind==0||rounds[c].credit==5)rounds[c].bonus+=bonus;
    if(rounds[c].hp<=0||rounds[c].dragon<=0){rounds[c].hp=75;rounds[c].dragon=100;}
    if(games[g].kind==0)Sound(g,1);
    // shortcut: original native win-category thresholds are unavailable; reserve jackpot sound for the actual jackpot.
    if(games[g].kind==1&&award>0)Sound(g,award>=40?25:24);
    if(games[g].kind==1&&award>0)Sound(g,30);
    Result(c,award,result,games[g].kind!=1||rounds[c].bonus==0);
    if(games[g].kind==1&&rounds[c].bonus>0)Show(c);
}
void StartWheel(int c){
    int g=GameOf(c);if(g<0||games[g].kind!=1||rounds[c].phase||rounds[c].bonus<=0)return;
    if(GetGameTime()<games[g].wheelLockedUntil)return;
    int wheel=Entity(games[g].wheel);
    if(wheel==-1){CasinoHint(c,"회전판이 없어 시작할 수 없습니다. 관리자에게 알려 주세요.");return;}
    StopSpin(g);StopWheelAudio(g,true);
    // shortcut: original server weights are unavailable; uniform sectors and a local virtual-chip pool.
    int target=GetRandomInt(0,23);rounds[c].wheelTarget=target;rounds[c].wheelAward=WheelPay(target);
    rounds[c].bonus--;rounds[c].wheelSpin=true;rounds[c].phase=1;rounds[c].due=GetGameTime()+WHEEL_SECONDS;
    rounds[c].wheelRound++;rounds[c].wheelStarted=GetGameTime();rounds[c].wheelTicks=0;
    rounds[c].wheelTravel=120+(target-games[g].wheelSector+24)%24;
    char sequence[32];Format(sequence,sizeof(sequence),"w_%d_%d",games[g].wheelSector,target);
    char idle[24];Format(idle,sizeof(idle),"idle_%d",target);SetVariantString(idle);AcceptEntityInput(wheel,"SetDefaultAnimation");
    Animate(games[g].wheel,sequence);
    // Drive the baked 15-second sequence from server time, including restarts after a frozen idle.
    SetEntProp(wheel,Prop_Send,"m_bClientSideAnimation",0);
    SetEntPropFloat(wheel,Prop_Send,"m_flPlaybackRate",0.0);
    games[g].wheelSector=target;Sound(g,9);
    rounds[c].result[0]=0;
    Label(g,rounds[c].result);Show(c);
}
void HoldWheel(int g){
    int wheel=Entity(games[g].wheel);if(wheel==-1)return;
    char idle[24];Format(idle,sizeof(idle),"idle_%d",games[g].wheelSector);
    SetVariantString(idle);AcceptEntityInput(wheel,"SetDefaultAnimation");
    Animate(games[g].wheel,idle);SetEntPropFloat(wheel,Prop_Send,"m_flPlaybackRate",0.0);
}
void FinishWheel(int c){
    int g=GameOf(c),target=rounds[c].wheelTarget;HoldWheel(g);
    rounds[c].wheelSpin=false;rounds[c].phase=0;rounds[c].wager=0;
    StopSpin(g);StopWheelAudio(g,true);
    if(target==23)rounds[c].bonus++;
    if(target==1){games[g].wheelLockedUntil=GetGameTime()+30.0;rounds[c].wheelAward=wheelPool.IntValue;wheelPool.IntValue=0;WheelCounters();}
    Sound(g,target==1?26:((rounds[c].wheelAward>0||target==23)?27:28));
    // Original wheel results also invoke DoWinEffects(false for prize, true for free spin).
    if(target==23)Sound(g,25);
    else if(target!=1&&rounds[c].wheelAward>0)Sound(g,24);
    if(rounds[c].wheelAward>0)Sound(g,target==1?31:30);
    Give(c,rounds[c].wheelAward);rounds[c].wheelTotal+=rounds[c].wheelAward;
    Format(rounds[c].result,sizeof(rounds[].result),"%d칩 획득",rounds[c].wheelAward);
    Label(g,rounds[c].result);
    Show(c);
}
void Bonus(int c,const char[] action){
    int g=GameOf(c);if(games[g].kind!=0)return;
    int damage;bool defend;
    if(StrEqual(action,"sword")){damage=GetRandomInt(15,25);Sound(g,2);}else if(StrEqual(action,"magic")){damage=GetRandomInt(5,40);Sound(g,5);}else if(StrEqual(action,"heal")){rounds[c].hp+=25;if(rounds[c].hp>75)rounds[c].hp=75;Sound(g,4);}else if(StrEqual(action,"defend")){defend=true;Sound(g,3);}else return;
    rounds[c].bonus--;rounds[c].dragon-=damage;
    if(rounds[c].dragon<=0){rounds[c].bonus=0;Sound(g,7);Result(c,500,"드래곤 처치 · 시험 보상");return;}
    rounds[c].hp-=defend?GetRandomInt(0,5):GetRandomInt(8,18);
    if(rounds[c].hp<=0){rounds[c].bonus=0;Result(c,0,"드래곤 전투 패배");}else Format(rounds[c].result,sizeof(rounds[].result),"전투: 나 %d / 드래곤 %d",rounds[c].hp,rounds[c].dragon);
}
void DrawPoker(int c){
    for(int i=0;i<5;i++)if(!(rounds[c].hold&(1<<i)))rounds[c].hand[i]=rounds[c].deck[rounds[c].cursor++];int hand[5];for(int i=0;i<5;i++)hand[i]=rounds[c].hand[i];int award=VideoPokerPay(hand,rounds[c].credit);char text[160];HandText(hand,5,text,sizeof(text));Sound(GameOf(c),award?12:10);Result(c,award,text);
}
void FinishBJ(int c){
    int value=BlackjackValue(rounds[c].hand,rounds[c].hc);bool natural=value==21&&rounds[c].hc==2;
    while(value<=21&&!natural&&BlackjackValue(rounds[c].dealer,rounds[c].dc)<17&&rounds[c].dc<12)rounds[c].dealer[rounds[c].dc++]=rounds[c].deck[rounds[c].cursor++];
    int house=BlackjackValue(rounds[c].dealer,rounds[c].dc),award;bool dn=house==21&&rounds[c].dc==2;
    if(value<=21){if(natural&&!dn)award=rounds[c].wager*5/2;else if(natural&&dn)award=rounds[c].wager;else if(!dn){if(house>21||value>house)award=rounds[c].wager*2;else if(value==house)award=rounds[c].wager;}}
    char text[128];Format(text,sizeof(text),"내 점수 %d / 딜러 %d (3:2 소수점 버림)",value,house);Sound(GameOf(c),award?15:14);Result(c,award,text);
}
void Buy(int c){
    int g=GameOf(c),kind=games[g].kind;if(games[g].phase>=2||chips[c]<10||(kind==5?rounds[c].cards>=4:rounds[c].contributed>0))return;
    chips[c]-=10;rounds[c].contributed+=10;games[g].pot+=10;
    if(kind==5){int at=rounds[c].cards*25;for(int col=0;col<5;col++){int pool[15];CasinoShuffle(pool,15);for(int row=0;row<5;row++)rounds[c].boards[at+row*5+col]=col*15+pool[row];}rounds[c].cards++;Sound(g,18);}
    if(games[g].phase==0){games[g].phase=1;games[g].due=GetGameTime()+(kind==5?10.0:50.0);Label(g,"BETTING OPEN");}
}
void Board(int c){
    int g=GameOf(c);Menu m=NewMenu(BoardHandler);char text[2048],line[256];Format(text,sizeof(text),"Planet Bingo · %d개 카드\n괄호: 호출된 번호 / 중앙 FREE",rounds[c].cards);
    for(int b=0;b<rounds[c].cards;b++){Format(line,sizeof(line),"\n카드 %d",b+1);StrCat(text,sizeof(text),line);for(int r=0;r<5;r++){StrCat(text,sizeof(text),"\n");for(int k=0;k<5;k++){int at=r*5+k,n=rounds[c].boards[b*25+at];if(at==12)strcopy(line,sizeof(line)," * ");else Format(line,sizeof(line),games[g].called[n]?"[%d] ":"%d ",n+1);StrCat(text,sizeof(text),line);}}}
    m.SetTitle("%s",text);m.AddItem("refresh","다시 확인");m.ExitBackButton=true;m.Display(c,MENU_TIME_FOREVER);
}
public int BoardHandler(Menu m,MenuAction a,int c,int item){if(a==MenuAction_End){EndMenu(m);return 0;}if(ending||!Player(c)||!seatSlot[c]||games[GameOf(c)].kind!=5)return 0;if(a==MenuAction_Select)Board(c);else if(a==MenuAction_Cancel&&item==MenuCancel_ExitBack)Show(c);return 0;}
void GroupRefresh(int g){for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c&&Player(c))Show(c);}}
void GroupFinish(int g){games[g].phase=3;games[g].due=GetGameTime()+15.0;for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c){rounds[c].contributed=0;rounds[c].cards=0;rounds[c].linePaid=false;}}games[g].pot=0;GroupRefresh(g);}
void BingoCall(int g){
    int n=games[g].order[games[g].count++];games[g].called[n]=true;Sound(g,18);char text[128];Format(text,sizeof(text),"BINGO CALL %d · %d/75",n+1,games[g].count);Label(g,text);
    int lineWinners[6],fullWinners[6],lc,fc;
    for(int i=0;i<6;i++){int c=Seated(g*6+i);if(!c)continue;bool line,full;for(int b=0;b<rounds[c].cards;b++){int card[25];for(int k=0;k<25;k++)card[k]=rounds[c].boards[b*25+k];line=line||BingoLine(card,games[g].called,false);full=full||BingoLine(card,games[g].called,true);}if(line&&!games[g].lineWon)lineWinners[lc++]=c;if(full)fullWinners[fc++]=c;}
    if(lc){games[g].lineWon=true;for(int i=0;i<lc;i++){int c=lineWinners[i];Give(c,games[g].pot/2/lc);PrintToChat(c,"[빙고] 첫 빙고! 반환 %d",games[g].pot/2/lc);}Sound(g,19);}
    if(fc){for(int i=0;i<fc;i++){int c=fullWinners[i];Give(c,(games[g].pot-games[g].pot/2)/fc);strcopy(rounds[c].result,sizeof(rounds[].result),"BLACKOUT 승리");}Sound(g,19);Label(g,"BLACKOUT!");GroupFinish(g);}
    else if(games[g].count>=75)GroupFinish(g);
    else games[g].due=GetGameTime()+bingoDelay.FloatValue;
}
void RaceFrame(int g,float now){
    float remaining=games[g].due-now;float fraction=1.0-remaining/raceDuration.FloatValue;if(fraction<0.0)fraction=0.0;if(fraction>1.0)fraction=1.0;
    for(int i=0;i<8;i++){int e=Entity(games[g].horses[i]);if(e==-1)continue;float p[3],a[3];float lead=i==games[g].winner?1.0:0.85+float(i)*0.01;float progress=fraction*lead+Sine(fraction*18.0+float(i))*0.012*Sine(fraction*FLOAT_PI);float theta=progress*FLOAT_PI*2.0,rotation=DegToRad(games[g].yaw),x=Cosine(theta)*(65.0+float(i)*2.0),y=Sine(theta)*(32.0+float(i)*1.5);p=games[g].origin;p[0]+=Cosine(rotation)*x-Sine(rotation)*y;p[1]+=Sine(rotation)*x+Cosine(rotation)*y;p[2]+=24.0;a[1]=RadToDeg(theta)+90.0+games[g].yaw;TeleportEntity(e,p,a,NULL_VECTOR);games[g].progress[i]=progress;}
    if(remaining<=0.0){char text[128];Format(text,sizeof(text),"WINNER: HORSE %d",games[g].winner+1);Label(g,text);for(int s=g*6;s<g*6+6;s++){int c=Seated(s);if(c&&rounds[c].contributed){int award=rounds[c].horse==games[g].winner?rounds[c].contributed*8:0;Give(c,award);Format(rounds[c].result,sizeof(rounds[].result),"우승 %d번 / 반환 %d",games[g].winner+1,award);}}Sound(g,21);GroupFinish(g);}
}
public void OnGameFrame(){
    if(!ready||ending)return;SeatsFrame();CasinoHintFrame();float now=GetGameTime();
    // Tick at pointer/sector crossings on the same integrated curve as the model, without catch-up bursts after lag.
    for(int c=1;c<=MaxClients;c++)if(Player(c)&&seatSlot[c]&&rounds[c].wheelSpin&&now<rounds[c].due){
        int wheel=Entity(games[GameOf(c)].wheel);
        if(wheel!=-1){
            float cycle=(now-rounds[c].wheelStarted)/WHEEL_SECONDS;
            if(cycle<0.0)cycle=0.0;if(cycle>0.998)cycle=0.998;
            SetEntPropFloat(wheel,Prop_Send,"m_flPlaybackRate",0.0);
            SetEntPropFloat(wheel,Prop_Send,"m_flCycle",cycle);
        }
        int ticks=RoundToFloor(WheelProgress(now-rounds[c].wheelStarted)*float(rounds[c].wheelTravel)+0.5);
        if(ticks>rounds[c].wheelTicks){rounds[c].wheelTicks=ticks;Sound(GameOf(c),8);}
    }
    if(now<nextFrame)return;nextFrame=now+0.1;
    for(int c=1;c<=MaxClients;c++)if(Player(c)&&seatSlot[c]){
        int g=GameOf(c),kind=games[g].kind;
        if(kind<=1&&rounds[c].phase==1&&!rounds[c].wheelSpin&&!rounds[c].reelStarted){if(now>=rounds[c].due)StartReels(c,now);else continue;}
        if(kind<=1&&rounds[c].phase==1&&!rounds[c].wheelSpin&&rounds[c].stops<3&&now>=rounds[c].nextStop){HoldReel(g,rounds[c].stops);rounds[c].stops++;rounds[c].nextStop+=slotDelay.FloatValue/3.0;Sound(g,23);}
        if(rounds[c].phase&&now>=rounds[c].due){
            if(kind==1&&rounds[c].wheelSpin)FinishWheel(c);
            else if(kind<=1)ResolveSlot(c);
            else if(kind==2)DrawPoker(c);else if(kind==3)FinishBJ(c);
            else if(kind==4){int n=rounds[c].draw[rounds[c].drawn++];if(rounds[c].picks[n])rounds[c].hits++;Sound(g,16);char text[128];Format(text,sizeof(text),"KENO %d · %d/20 · HIT %d",n+1,rounds[c].drawn,rounds[c].hits);Label(g,text);if(rounds[c].drawn==20){int pay=KenoPay(rounds[c].picked,rounds[c].hits)*rounds[c].wager;Sound(g,17);Result(c,pay,text);}else rounds[c].due=now+0.5;}
        }
    }
    for(int g=0;g<GAMES;g++)if(games[g].phase){
        if(games[g].kind==6&&games[g].phase==2){RaceFrame(g,now);continue;}
        if(now<games[g].due)continue;
        if(games[g].phase==1){games[g].phase=2;games[g].count=0;games[g].lineWon=false;for(int i=0;i<80;i++)games[g].called[i]=false;if(games[g].kind==5){CasinoShuffle(games[g].order,75);games[g].due=now+bingoDelay.FloatValue;}else{games[g].winner=GetRandomInt(0,7);games[g].due=now+raceDuration.FloatValue;Sound(g,20);}Label(g,"ROUND STARTED · BETTING CLOSED");GroupRefresh(g);}
        else if(games[g].phase==2)BingoCall(g);
        else{games[g].phase=0;Label(g,"READY · TEST ODDS / VIRTUAL CHIPS");GroupRefresh(g);}
    }
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float velocity[3],float angles[3],int &weapon){
    if(!ready||!Player(c))return Plugin_Continue;int old=previous[c];previous[c]=buttons;
    if(!seatSlot[c]){if((buttons&IN_USE)&&!(old&IN_USE)&&GetGameTime()>=nextUse[c]){nextUse[c]=GetGameTime()+0.3;SeatUse(c);}return Plugin_Continue;}
    if((buttons&IN_DUCK)&&!(old&IN_DUCK)){SeatStop(c,true);if(!seatSlot[c])return Plugin_Continue;}
    if((buttons&IN_ATTACK3)&&!(old&IN_ATTACK3))seatThird[c]=!seatThird[c];
    if((buttons&IN_USE)&&!(old&IN_USE)&&GetGameTime()>=nextUse[c]){nextUse[c]=GetGameTime()+0.3;if(!ExtraUse(c))Show(c);}
    if((buttons&IN_JUMP)&&!(old&IN_JUMP)&&games[GameOf(c)].kind<=1)Start(c);
    buttons&=~(IN_ATTACK|IN_ATTACK2|IN_ATTACK3|IN_JUMP|IN_DUCK|IN_USE|IN_RELOAD|IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT);buttons|=IN_DUCK;weapon=0;SeatPhysicsHold(c);velocity[0]=velocity[1]=velocity[2]=0.0;return Plugin_Changed;
}
public Action SelfTest(int c,int args){ExpansionRulesTest();int before=menus.Length;Menu probe=NewMenu(PlayHandler);EndMenu(probe);EndMenu(probe);if(menus.Length!=before)SetFailState("Expansion menu lifecycle");int n;if(!ExtraNumber("12",1,n)||ExtraNumber("13",1,n)||ExtraNumber("5x",2,n)||!ExtraNumber("2000",2,n))SetFailState("Expansion input bounds");ReplyToCommand(c,"CasinoExpansion 0.2.4 rules PASS / assets=%d / virtual chips only",ready);return Plugin_Handled;}
