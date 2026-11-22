#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "casino_hint.inc"

// Independent TF2 reconstruction. Probabilities/timings are NOT Tower Unite's.
#define COUNT 64
#define RESULT_COOLDOWN 0.5
#define WIN_FX_COUNT 20
#define JACKPOT_SOUND_SECONDS 7.909093
#define BIG_WIN_LEAD_SECONDS 1.5
#define BIG_WIN_SECONDS 2.769252
#define COIN_DUMP_SECONDS 2.769240
#define SCALE 1.0
#define BASE_HEIGHT 41.57475584
#define BODY "models/tower_slots_v8/cabinet.mdl"
#define REEL "models/tower_slots_v3/reel.mdl"
#define JACKDIGIT "models/tower_slots_v6/jackdigit.mdl"
#define CREDITDIGIT "models/tower_slots_v6/creditdigit.mdl"
#define PAYHIGHLIGHT "models/tower_slots_highlight_v1/highlight.mdl"
// Use the seat camera for first person too; native duck prediction overrides view height.
public Plugin myinfo={name="Tower Slots Test",author="Codex",description="Triple Diamonds animated prototype; no economy",version="0.8.8"};
enum struct Machine {
    int body;
    int highlight;
    int light;
    int chair;
    float chairOrigin[3];
    int reel[3];
    int symbol[3];
    int user;
    int category;
    int stopped;
    int digits[9];
    int bet;
    float origin[3];
    float yaw;
    float start;
    float readyAt;
    int previousSymbol[3];
    bool spinning;
    float nextSpinSound;
    bool busy;
    bool testSpin;
    int celebration[WIN_FX_COUNT];
    float celebrationUntil;
    float celebrationCoinUntil;
    float celebrationRepeat;
    bool celebrationJackpot;
    bool celebrationAlternate;
    float celebrationYaw;
    float payoutSoundAt;
    float bigSoundAt;
}
Machine machines[COUNT];
bool ready;
int previous[MAXPLAYERS+1];
ConVar weights[9],sharedPool;
// Symbols: diamond, cherry, watermelon, orange, grapes, bar.
int payout[]={10000,130,120,90,60,30,15,10,0};
char names[][]={"다이아","체리","수박","오렌지","포도","BAR"};
char sounds[][]={"tower_slots_v2/SlotMachineCrank.wav","tower_slots_v2/SlotMachineSpinLoop.wav","tower_slots_v2/SlotThunk.wav","tower_slots_v2/DiamondMinorWin.wav","tower_slots_v2/DiamondMajorWin.wav","tower_slots_v2/DiamondJackpot.wav","tower_slots_v3/SlotMachineCoinDump.wav","tower_slots_v3/SlotMachineWinBig.wav"};
char winParticles[][]={"taunt_totalscoutdeath_split_money","unusual_australian_coinrain","mvm_pow_gold_seq","contract_completed_primary_dollars"};
ConVar reelX,reelY,reelZ,reelGap;
#include "tower_slots_seats.inc"
#include "tower_slots_setup.inc"

public void OnPluginStart() {
    int expected[]={5,4,4,4,3,3,3,3};for(int i=0;i<8;i++)if(WinSound(i)!=expected[i])SetFailState("Win sound mapping failed");
    SeatsInit();SlotSetupInit();
    for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c))OnClientPutInServer(c);
    sharedPool=CreateConVar("sm_towerslot_shared_pool","0","Shared cosmetic jackpot; no real currency",FCVAR_DONTRECORD,true,0.0,true,99999999.0);
    RegAdminCmd("sm_towerslot",Spawn,ADMFLAG_GENERIC);
    RegAdminCmd("sm_towerslot_clear",Clear,ADMFLAG_GENERIC);
    RegAdminCmd("sm_towerslot_status",Status,ADMFLAG_GENERIC);
    RegAdminCmd("sm_towerslot_soundtest",SoundTest,ADMFLAG_GENERIC);
    RegAdminCmd("sm_towerslot_seatverify",SeatVerify,ADMFLAG_ROOT);
    AddCommandListener(Chat,"say");AddCommandListener(Chat,"say_team");
    AddCommandListener(Voice,"voicemenu");
    char key[64];char defaults[][]={"10","300","500","600","700","800","400","1500","5190"};
    for(int i=0;i<9;i++) {
        Format(key,sizeof(key),"sm_towerslot_weight_%d",i);
        weights[i]=CreateConVar(key,defaults[i],"Outcome weight: 0-5 triples, 6 two diamonds, 7 one diamond, 8 loss",0,true,0.0,true,100000.0);
    }
    // Package transforms converted to the exported mesh scale, matched to
    // cabinet openings Y=[-6.4,-3.2],[-1.6,1.6],[3.2,6.4], Z=20..25.35.
    reelX=CreateConVar("sm_towerslot_reel_x","-1.51564","Reel axle depth");
    reelY=CreateConVar("sm_towerslot_reel_y","-6.4","First reel lateral offset");
    reelZ=CreateConVar("sm_towerslot_reel_z","21.76366","Reel axle height");
    reelGap=CreateConVar("sm_towerslot_reel_gap","4.8","Reel spacing");
    AutoExecConfig(true,"tower_slots_test");
}
public void OnMapStart() {
    CasinoHintReset();
    ready=false;
    for(int c=1;c<=MaxClients;c++)testOutcome[c]=0;
    for(int s=0;s<COUNT;s++) {Machine empty;machines[s]=empty;}
    char path[PLATFORM_MAX_PATH],line[PLATFORM_MAX_PATH];
    BuildPath(Path_SM,path,sizeof(path),"configs/tower_slots_downloads.txt");
    File f=OpenFile(path,"r");if(f==null)return;
    bool missing;
    while(f.ReadLine(line,sizeof(line))) {
        TrimString(line);if(!line[0])continue;
        if(!FileExists(line,true)){LogError("Tower slot missing %s",line);missing=true;}
        else AddFileToDownloadsTable(line);
    }
    delete f;if(missing)return;
    if(!PrecacheModel(BODY,true)||!PrecacheModel(REEL,true)||!PrecacheModel(JACKDIGIT,true)||!PrecacheModel(CREDITDIGIT,true)||!PrecacheModel(PAYHIGHLIGHT,true))return;
    for(int i=0;i<sizeof(sounds);i++)if(!PrecacheSound(sounds[i],true))return;
    if(!PrecacheSound("double_nothing_v3/button_down.wav",true))return;
    PrecacheGeneric("particles/taunt_fx.pcf",true);
    PrecacheGeneric("particles/summer2023_unusuals.pcf",true);
    PrecacheGeneric("particles/mvm.pcf",true);PrecacheGeneric("particles/item_fx.pcf",true);
    int table=FindStringTable("ParticleEffectNames");if(table==INVALID_STRING_TABLE)return;
    bool locked=LockStringTables(false);
    for(int i=0;i<sizeof(winParticles);i++)if(FindStringIndex(table,winParticles[i])==INVALID_STRING_INDEX)AddToStringTable(table,winParticles[i]);
    LockStringTables(locked);
    ready=SeatsPrecache();
}
bool Player(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&IsPlayerAlive(c);}
int Entity(int ref){int e=EntRefToEntIndex(ref);return e>MaxClients&&IsValidEntity(e)?e:-1;}
void Remove(int s) {
    ClearCelebration(s);
    for(int c=1;c<=MaxClients;c++)if(seatSlot[c]==s+1)SeatStop(c,false);
    int chair=Entity(machines[s].chair);if(chair!=-1)RemoveEntity(chair);
    int highlight=Entity(machines[s].highlight);if(highlight!=-1)RemoveEntity(highlight);
    int light=Entity(machines[s].light);if(light!=-1)RemoveEntity(light);
    int e=Entity(machines[s].body);
    if(e!=-1){StopSound(e,SNDCHAN_STATIC,sounds[1]);StopSound(e,SNDCHAN_ITEM,sounds[5]);StopSound(e,SNDCHAN_ITEM,sounds[6]);StopSound(e,SNDCHAN_VOICE,sounds[7]);RemoveEntity(e);}
    for(int i=0;i<3;i++){e=Entity(machines[s].reel[i]);if(e!=-1)RemoveEntity(e);}
    for(int i=0;i<9;i++){e=Entity(machines[s].digits[i]);if(e!=-1)RemoveEntity(e);}
    Machine empty;machines[s]=empty;
}
public void OnPluginEnd(){SlotMenusShutdown();for(int s=0;s<COUNT;s++)Remove(s);}
public void OnMapEnd(){ready=false;for(int c=1;c<=MaxClients;c++)SeatStop(c,false);for(int s=0;s<COUNT;s++){Machine empty;machines[s]=empty;}}
public void OnClientPutInServer(int c){SDKHook(c,SDKHook_OnTakeDamage,SeatDamage);}
public Action SeatDamage(int victim,int &attacker,int &inflictor,float &damage,int &damageType){
    if(!seatSlot[victim])return Plugin_Continue;
    damage=0.0;return Plugin_Handled;
}
public void OnClientDisconnect(int c){seatDiscard[c]=true;SeatStop(c,false);previous[c]=0;inputMode[c]=0;installCount[c]=0;installSpacing[c]=0.0;testOutcome[c]=0;}
public bool TraceWorld(int e,int mask,any data){return e==0;}
int Prop(const char[] model,bool solid=false) {
    int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return 0;
    DispatchKeyValue(e,"model",model);DispatchKeyValue(e,"solid",solid?"6":"0");
    if(!DispatchSpawn(e)){RemoveEntity(e);return 0;}
    SetEntProp(e,Prop_Data,"m_takedamage",0);
    return EntIndexToEntRef(e);
}
void Animate(int ref,const char[] sequence){
    int e=Entity(ref);if(e==-1)return;
    SetVariantString(sequence);AcceptEntityInput(e,"SetAnimation");
    SetEntPropFloat(e,Prop_Send,"m_flCycle",0.0);
    SetEntPropFloat(e,Prop_Send,"m_flPlaybackRate",1.0);
}
void WorldPoint(int s,float x,float y,float z,float p[3]) {
    float rad=DegToRad(machines[s].yaw);
    p[0]=machines[s].origin[0]+SCALE*(Cosine(rad)*x-Sine(rad)*y);
    p[1]=machines[s].origin[1]+SCALE*(Sine(rad)*x+Cosine(rad)*y);
    p[2]=machines[s].origin[2]+SCALE*(BASE_HEIGHT+z);
}
void Position(int s,int ref,float x,float y,float z) {
    int e=Entity(ref);if(e==-1)return;
    float p[3],a[3];WorldPoint(s,x,y,z,p);
    // studiomdl rotated SMD vertices +90 degrees about Z: (x,y,z)->(-y,x,z).
    // Only placement uses entity transforms. All motion is baked bone animation.
    a[0]=0.0;a[1]=machines[s].yaw-90.0;a[2]=0.0;
    TeleportEntity(e,p,a,NULL_VECTOR);
}
void UpdateCounters(int s) {
    int value=sharedPool.IntValue;
    for(int i=7;i>=0;i--){
        int skin=(value>0||i==7)?value%10:10;value/=10;
        int e=Entity(machines[s].digits[i]);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",skin);
    }
    int e=Entity(machines[s].digits[8]);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",machines[s].bet);
    e=Entity(machines[s].highlight);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",(machines[s].bet-1)/2);
    e=Entity(machines[s].body);if(e!=-1)SetEntProp(e,Prop_Send,"m_nSkin",(machines[s].bet+1)/2);
}
public Action Spawn(int c,int args){SpawnBatch(c,1,100.0);return Plugin_Handled;}
int CreateMachine(const float p[3],float yaw){
    int s=-1;for(int i=0;i<COUNT;i++)if(Entity(machines[i].body)==-1){Remove(i);s=i;break;}
    if(s==-1)return -1;
    machines[s].origin=p;machines[s].yaw=yaw;machines[s].bet=1;
    if(!CreateChair(s)){Remove(s);return -1;}
    machines[s].body=Prop(BODY,true);
    machines[s].highlight=Prop(PAYHIGHLIGHT);
    for(int i=0;i<3;i++)machines[s].reel[i]=Prop(REEL);
    for(int i=0;i<9;i++)machines[s].digits[i]=Prop(i<8?JACKDIGIT:CREDITDIGIT);
    bool valid=Entity(machines[s].body)!=-1&&Entity(machines[s].highlight)!=-1;
    for(int i=0;i<3;i++)if(Entity(machines[s].reel[i])==-1)valid=false;
    for(int i=0;i<9;i++)if(Entity(machines[s].digits[i])==-1)valid=false;
    if(!valid){Remove(s);return -1;}
    Position(s,machines[s].body,0.0,0.0,0.0);
    Position(s,machines[s].highlight,0.0,0.0,0.0);
    Animate(machines[s].body,"idle");
    for(int i=0;i<3;i++){
        SetVariantFloat(SCALE);AcceptEntityInput(Entity(machines[s].reel[i]),"SetModelScale");
        Position(s,machines[s].reel[i],reelX.FloatValue,reelY.FloatValue+float(i)*reelGap.FloatValue,reelZ.FloatValue);
        machines[s].previousSymbol[i]=1;Animate(machines[s].reel[i],"idle_1");
    }
    // Separate coplanar glyph/background surfaces without a floating display.
    for(int i=0;i<8;i++)Position(s,machines[s].digits[i],4.22,(float(i)-3.5)*2.05,46.208);
    Position(s,machines[s].digits[8],5.10,5.7,42.048);UpdateCounters(s);
    int light=CreateEntityByName("light_dynamic");
    if(light==-1){Remove(s);return -1;}
    machines[s].light=EntIndexToEntRef(light);
    DispatchKeyValue(light,"_light","255 224 180 255");
    DispatchKeyValue(light,"brightness","2");DispatchKeyValue(light,"distance","90");
    DispatchKeyValue(light,"style","0");DispatchKeyValue(light,"spotlight_radius","0");
    if(!DispatchSpawn(light)){Remove(s);return -1;}
    float lamp[3];WorldPoint(s,24.0,0.0,30.0,lamp);TeleportEntity(light,lamp,NULL_VECTOR,NULL_VECTOR);
    AcceptEntityInput(light,"TurnOn");
    return s;
}

public Action Clear(int c,int args){for(int s=0;s<COUNT;s++)Remove(s);ReplyToCommand(c,"[타워슬롯] 테스트 기계를 모두 제거했습니다.");return Plugin_Handled;}
public Action Status(int c,int args){
    int count,busy;for(int s=0;s<COUNT;s++)if(Entity(machines[s].body)!=-1){count++;if(machines[s].busy)busy++;}
    int seated;for(int i=1;i<=MaxClients;i++)if(seatSlot[i])seated++;
    ReplyToCommand(c,"Tower Slots 0.8.7 ready=%d economy=disabled machines=%d busy=%d seated=%d cooldown=%.1f",ready,count,busy,seated,RESULT_COOLDOWN);return Plugin_Handled;
}
public Action SoundTest(int c,int args){
    if(!Player(c)||!ready)return Plugin_Handled;
    EmitSoundToClient(c,sounds[0],c,SNDCHAN_AUTO,SNDLEVEL_NONE);
    ReplyToCommand(c,"[타워슬롯] 레버 음원 직접 재생. 안 들리면 콘솔의 사운드 오류를 확인해주세요.");return Plugin_Handled;
}
void Sound(int s,int i){
    int e=Entity(machines[s].body);if(e==-1)return;
    if(i==5){StopSound(e,SNDCHAN_ITEM,sounds[6]);StopSound(e,SNDCHAN_VOICE,sounds[7]);machines[s].payoutSoundAt=0.0;machines[s].bigSoundAt=GetGameTime()+JACKPOT_SOUND_SECONDS-BIG_WIN_LEAD_SECONDS;}
    if(i==7){machines[s].payoutSoundAt=GetGameTime()+BIG_WIN_SECONDS;machines[s].celebrationUntil=GetGameTime()+BIG_WIN_SECONDS+COIN_DUMP_SECONDS;}
    float pos[3];WorldPoint(s,0.0,0.0,26.0,pos);
    EmitSoundToAll(sounds[i],e,i==1?SNDCHAN_STATIC:(i==7?SNDCHAN_VOICE:(i>=5?SNDCHAN_ITEM:SNDCHAN_AUTO)),SNDLEVEL_NORMAL,SND_NOFLAGS,1.0,SNDPITCH_NORMAL,-1,pos,NULL_VECTOR,false);
}
void ClearCelebration(int s){
    for(int i=0;i<WIN_FX_COUNT;i++){
        int e=Entity(machines[s].celebration[i]);if(e!=-1)RemoveEntity(e);
        machines[s].celebration[i]=INVALID_ENT_REFERENCE;
    }
    machines[s].celebrationUntil=0.0;
    machines[s].celebrationCoinUntil=machines[s].celebrationRepeat=0.0;machines[s].celebrationJackpot=false;
    machines[s].celebrationAlternate=false;
}
void WinEmitter(int s,int index,int effect,float yaw){
    int old=Entity(machines[s].celebration[index]);if(old!=-1)RemoveEntity(old);
    machines[s].celebration[index]=INVALID_ENT_REFERENCE;
    if(GetEntityCount()>=GetMaxEntities()-32){LogError("Slot effect skipped: entity reserve");return;}
    int e=CreateEntityByName("info_particle_system");if(e==-1){LogError("Slot celebration creation failed");return;}
    machines[s].celebration[index]=EntIndexToEntRef(e);
    DispatchKeyValue(e,"effect_name",winParticles[effect]);DispatchKeyValue(e,"start_active","0");
    char target[64];Format(target,sizeof(target),"tower_win_%d_%d",e,GetGameTickCount());
    DispatchKeyValue(e,"targetname",target);DispatchKeyValue(e,"cpoint1",target);
    float p[3],a[3];WorldPoint(s,0.0,0.0,30.0,p);
    p[0]+=Cosine(DegToRad(yaw))*12.0;p[1]+=Sine(DegToRad(yaw))*12.0;
    // Split-money velocity uses local Z at CP1; tilt that axis toward the rider.
    a[0]=effect==0?65.0:0.0;a[1]=yaw;
    TeleportEntity(e,p,a,NULL_VECTOR);
    if(!DispatchSpawn(e)){RemoveEntity(e);machines[s].celebration[index]=INVALID_ENT_REFERENCE;return;}
    ActivateEntity(e);AcceptEntityInput(e,"Start");
}
void Celebrate(int s,int category){
    if(category<0||category>=8)return;
    if(category!=0&&machines[s].celebrationJackpot&&GetGameTime()<machines[s].celebrationUntil)return;
    ClearCelebration(s);
    machines[s].celebrationYaw=machines[s].yaw;
    int c=GetClientOfUserId(machines[s].user);
    if(Player(c)){
        float p[3],rider[3],delta[3],a[3];WorldPoint(s,0.0,0.0,30.0,p);GetClientAbsOrigin(c,rider);
        MakeVectorFromPoints(p,rider,delta);GetVectorAngles(delta,a);machines[s].celebrationYaw=a[1];
    }
    machines[s].celebrationJackpot=category==0;
    if(category==0){
        for(int direction=0;direction<5;direction++){
            float yaw=machines[s].celebrationYaw+float(direction)*72.0;
            for(int effect=1;effect<=3;effect++)WinEmitter(s,direction*4+effect-1,effect,yaw);
        }
        machines[s].celebrationUntil=GetGameTime()+JACKPOT_SOUND_SECONDS-BIG_WIN_LEAD_SECONDS+BIG_WIN_SECONDS+COIN_DUMP_SECONDS;
        machines[s].celebrationRepeat=GetGameTime()+2.25;
    }else{
        WinEmitter(s,0,0,machines[s].celebrationYaw);WinEmitter(s,1,1,machines[s].celebrationYaw);
        machines[s].celebrationCoinUntil=GetGameTime()+1.0;machines[s].celebrationUntil=GetGameTime()+3.0;
    }
}
void UpdateCelebration(int s,float now){
    if(machines[s].celebrationUntil<=0.0)return;
    if(now>=machines[s].celebrationUntil){ClearCelebration(s);return;}
    if(machines[s].celebrationCoinUntil>0.0&&now>=machines[s].celebrationCoinUntil){
        int e=Entity(machines[s].celebration[1]);if(e!=-1)RemoveEntity(e);
        machines[s].celebration[1]=INVALID_ENT_REFERENCE;machines[s].celebrationCoinUntil=0.0;
    }
    if(machines[s].celebrationJackpot&&now>=machines[s].celebrationRepeat){
        machines[s].celebrationAlternate=!machines[s].celebrationAlternate;
        for(int direction=0;direction<5;direction++){
            float yaw=machines[s].celebrationYaw+float(direction)*72.0;
            WinEmitter(s,direction*4+1,2,yaw);
            // Dollars start after 0.7s: overlap two batches to avoid emission gaps.
            WinEmitter(s,direction*4+(machines[s].celebrationAlternate?3:2),3,yaw);
        }
        machines[s].celebrationRepeat=now+2.25;
    }
}
int Choose() {
    int total;for(int i=0;i<9;i++)total+=weights[i].IntValue;
    if(total<=0)return 8;
    int n=GetRandomInt(1,total);for(int i=0;i<9;i++){n-=weights[i].IntValue;if(n<=0)return i;}return 8;
}
int WinSound(int category){return category==0?5:(category>=1&&category<=3?4:3);}
int SettleReward(int category,int &bank){
    if(category==0){int reward=bank;bank=0;return reward;}
    return category>=1&&category<8?payout[category]:0;
}
void UpdateAllCounters(){for(int s=0;s<COUNT;s++)if(Entity(machines[s].body)!=-1)UpdateCounters(s);}
void Start(int s,int c) {
    if(!Player(c)||seatSlot[c]!=s+1)return;
    if(machines[s].busy||GetGameTime()<machines[s].readyAt)return;
    if(!SlotAdmin(c))testOutcome[c]=0;
    bool testing=testOutcome[c]>0;
    int deposit=(machines[s].bet+1)/2;
    if(testing)deposit=0;
    if(sharedPool.IntValue>99999999-deposit){PrintToChat(c,"[타워슬롯] 테스트 누적 표시 한도에 도달했습니다.");return;}
    sharedPool.IntValue+=deposit;UpdateAllCounters();
    int result=testing?testOutcome[c]-1:Choose();testOutcome[c]=0;machines[s].testSpin=testing;machines[s].category=result;
    if(testing)PrintToChat(c,"[슬롯 테스트] 지정 결과 적용. 이번 회전은 공용 누적금에 영향을 주지 않습니다.");
    if(result<6){for(int i=0;i<3;i++)machines[s].symbol[i]=result;}
    else {
        for(int i=0;i<3;i++)machines[s].symbol[i]=GetRandomInt(1,5);
        if(result==6){int other=GetRandomInt(0,2);for(int i=0;i<3;i++)if(i!=other)machines[s].symbol[i]=0;}
        else if(result==7)machines[s].symbol[GetRandomInt(0,2)]=0;
        else if(machines[s].symbol[0]==machines[s].symbol[1]&&machines[s].symbol[1]==machines[s].symbol[2])machines[s].symbol[2]=machines[s].symbol[2]%5+1;
    }
    machines[s].user=GetClientUserId(c);machines[s].start=GetGameTime();machines[s].stopped=0;machines[s].busy=true;machines[s].spinning=false;
    UpdateCounters(s);
    Animate(machines[s].body,"leverpull");Sound(s,0);
    LogMessage("Tower spin start slot=%d user=%d bet=%d deposit=%d jackpot=%d",s,machines[s].user,machines[s].bet,deposit,sharedPool.IntValue);
}
public bool TraceObstacles(int e,int mask,any s) {
    if(e>0&&e<=MaxClients)return false;
    if(e==Entity(machines[s].body))return false;
    if(e==Entity(machines[s].chair))return false;
    if(e==Entity(machines[s].highlight))return false;
    for(int i=0;i<3;i++)if(e==Entity(machines[s].reel[i]))return false;
    for(int i=0;i<9;i++)if(e==Entity(machines[s].digits[i]))return false;
    return true;
}
bool Use(int c) {
    if(!Player(c)||!ready)return false;
    if(!seatSlot[c])return SeatUse(c);
    float eye[3],angles[3],direction[3];SeatAim(c,eye,angles);GetAngleVectors(angles,direction,NULL_VECTOR,NULL_VECTOR);
    int best=-1,action=-1;float closest=120.0;
    for(int s=seatSlot[c]-1;s<seatSlot[c];s++)if(Entity(machines[s].body)!=-1) {
        for(int b=0;b<4;b++){
            float p[3],delta[3];
            if(b<3)WorldPoint(s,8.0888,5.86025+float(b)*1.92,18.7635,p);
            else WorldPoint(s,4.79839,15.0,32.5,p);
            MakeVectorFromPoints(eye,p,delta);float along=GetVectorDotProduct(delta,direction);
            if(along<1.0||along>=closest)continue;
            float radius=(b<3?0.93:4.0)*SCALE;
            if(GetVectorLength(delta,true)-along*along>radius*radius)continue;
            // Controls are on the front; do not operate them through the cabinet.
            float rad=DegToRad(machines[s].yaw);
            if((eye[0]-p[0])*Cosine(rad)+(eye[1]-p[1])*Sine(rad)<0.0)continue;
            Handle trace=TR_TraceRayFilterEx(eye,p,MASK_SOLID,RayType_EndPoint,TraceObstacles,s);
            bool blocked=TR_DidHit(trace);delete trace;if(blocked)continue;
            best=s;action=b;closest=along;
        }
    }
    if(best==-1)return false;
    if(machines[best].busy||GetGameTime()<machines[best].readyAt)return true;
    if(action<3){machines[best].bet=1+action*2;UpdateCounters(best);EmitSoundToAll("double_nothing_v3/button_down.wav",Entity(machines[best].body));CasinoHint(c,"베팅 %d 토큰 · 레버를 보고 E: 회전",machines[best].bet);}
    else Start(best,c);
    return true;
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float vel[3],float angles[3],int &weapon) {
    int old=previous[c];bool pressed=(buttons&IN_USE)!=0&&(old&IN_USE)==0;previous[c]=buttons;
    if(seatSlot[c]){
        if((buttons&IN_DUCK)&&!(old&IN_DUCK)){SeatStop(c,true);if(!seatSlot[c])return Plugin_Changed;}
        if((buttons&IN_ATTACK3)&&!(old&IN_ATTACK3))seatThird[c]=!seatThird[c];
        if(pressed)Use(c);
        if((buttons&IN_JUMP)&&!(old&IN_JUMP)&&ready)Start(seatSlot[c]-1,c);
        buttons&=~(IN_ATTACK|IN_ATTACK2|IN_ATTACK3|IN_JUMP|IN_DUCK|IN_USE|IN_RELOAD|IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT);
        // Raw Ctrl edges were read above; keep the server-side stance crouched.
        buttons|=IN_DUCK;SeatPhysicsHold(c);
        vel[0]=vel[1]=vel[2]=0.0;weapon=0;return Plugin_Changed;
    }
    if(pressed&&Use(c)){buttons&=~IN_USE;return Plugin_Changed;}return Plugin_Continue;
}
public Action Voice(int c,const char[] command,int argc) {
    char a[8],b[8];GetCmdArg(1,a,sizeof(a));GetCmdArg(2,b,sizeof(b));
    return StrEqual(a,"0")&&StrEqual(b,"0")&&Use(c)?Plugin_Handled:Plugin_Continue;
}
public Action Chat(int c,const char[] command,int argc) {
    char text[64];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);
    bool clear=StrEqual(text,"!타워슬롯삭제");
    if(!clear&&!StrEqual(text,"!타워슬롯"))return Plugin_Continue;
    if(!CheckCommandAccess(c,clear?"sm_towerslot_clear":"sm_towerslot",ADMFLAG_GENERIC))return Plugin_Handled;
    if(clear)Clear(c,0);else Spawn(c,0);return Plugin_Handled;
}
public void OnGameFrame() {
    CasinoHintFrame();
    SeatsFrame();
    if(!ready)return;float now=GetGameTime();
    for(int s=0;s<COUNT;s++){
        if(machines[s].bigSoundAt>0.0&&now>=machines[s].bigSoundAt){machines[s].bigSoundAt=0.0;Sound(s,7);}
        if(machines[s].payoutSoundAt>0.0&&now>=machines[s].payoutSoundAt){machines[s].payoutSoundAt=0.0;Sound(s,6);}
        UpdateCelebration(s,now);
    }
    for(int s=0;s<COUNT;s++)if(machines[s].busy) {
        if(Entity(machines[s].body)==-1){Remove(s);continue;}
        float elapsed=now-machines[s].start;
        int lastStop=machines[s].symbol[0]==machines[s].symbol[1]?5:3;
        if(!machines[s].spinning){
            if(elapsed<1.0)continue;
            Animate(machines[s].body,"idle");
            for(int i=0;i<3;i++){
                char sequence[32];Format(sequence,sizeof(sequence),"r_%d_%d_%d",machines[s].previousSymbol[i],machines[s].symbol[i],i==2?lastStop:i+1);
                Animate(machines[s].reel[i],sequence);
            }
            machines[s].spinning=true;machines[s].start=now;elapsed=0.0;
            Sound(s,1);machines[s].nextSpinSound=now+0.73;
        }
        if(elapsed<float(lastStop)&&now>=machines[s].nextSpinSound){Sound(s,1);machines[s].nextSpinSound=now+0.73;}
        for(int i=0;i<3;i++) {
            float duration=float(i==2?lastStop:i+1);
            if(elapsed>=duration&&machines[s].stopped==i){
                machines[s].stopped++;machines[s].previousSymbol[i]=machines[s].symbol[i];Sound(s,2);
            }
        }
        if(machines[s].stopped==3) {
            machines[s].busy=false;UpdateCounters(s);int e=Entity(machines[s].body);if(e!=-1)StopSound(e,SNDCHAN_STATIC,sounds[1]);
            LogMessage("Tower spin end slot=%d category=%d",s,machines[s].category);
            int result=machines[s].category;
            if(result<8){Celebrate(s,result);int c=GetClientOfUserId(machines[s].user);
                int bank=sharedPool.IntValue;int reward=SettleReward(result,bank);
                Sound(s,WinSound(result));
                if(!machines[s].testSpin){sharedPool.IntValue=bank;if(result==0)UpdateAllCounters();}
                LogMessage("Tower award slot=%d category=%d reward=%d jackpot_remaining=%d",s,result,reward,sharedPool.IntValue);
                if(c>0&&IsClientInGame(c))CasinoHint(c,"%s / %s / %s\n%d 획득 (테스트)",names[machines[s].symbol[0]],names[machines[s].symbol[1]],names[machines[s].symbol[2]],reward);}
            machines[s].readyAt=now+RESULT_COOLDOWN;
        }
    }
}
