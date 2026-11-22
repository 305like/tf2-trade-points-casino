#include <tf2_stocks>
#include <sdkhooks>

#define CHAIR_MODEL "models/casino_seats/v2/chair.mdl"
char seatClasses[][]={"","scout","sniper","soldier","demo","medic","heavy","pyro","spy","engineer"};
float seatEyes[]={0.0,76.4,79.6,83.5,78.7,79.2,89.2,80.0,80.6,79.0};
int seatSlot[MAXPLAYERS+1],seatBody[MAXPLAYERS+1],seatSkin[MAXPLAYERS+1],seatGroups[MAXPLAYERS+1],seatAnimations[MAXPLAYERS+1];
bool seatThird[MAXPLAYERS+1];
char seatOldModel[MAXPLAYERS+1][PLATFORM_MAX_PATH];
RenderFx seatFx[MAXPLAYERS+1];
float seatOldEye[MAXPLAYERS+1][3],seatEntry[MAXPLAYERS+1][3];
MoveType seatMove[MAXPLAYERS+1];
#define SEAT_CAMERA_RIG "models/casino_seats/camera_v1.mdl"
#define SEAT_CAMERA_MODEL "models/empty.mdl"
Handle seatCrosshair;
bool seatDiscard[MAXPLAYERS+1];
ConVar seatPushaway;
char seatPhysicsProps[][]={"m_nSolidType","m_usSolidFlags","m_CollisionGroup","m_bDucked","m_bDucking"};
int seatPhysicsSaved[MAXPLAYERS+1][5],seatDuckFlag[MAXPLAYERS+1];

void SeatPhysicsSave(int c){
    for(int i=0;i<sizeof(seatPhysicsProps);i++)seatPhysicsSaved[c][i]=GetEntProp(c,Prop_Send,seatPhysicsProps[i]);
    seatDuckFlag[c]=GetEntityFlags(c)&FL_DUCKING;
}
void SeatPhysicsHold(int c){
    SetEntProp(c,Prop_Send,"m_nSolidType",0);
    SetEntProp(c,Prop_Send,"m_usSolidFlags",seatPhysicsSaved[c][1]|4); // FSOLID_NOT_SOLID
    SetEntProp(c,Prop_Send,"m_CollisionGroup",2); // DEBRIS_TRIGGER: no player collision
    SetEntProp(c,Prop_Send,"m_bDucked",1);SetEntProp(c,Prop_Send,"m_bDucking",0);
    SetEntityFlags(c,GetEntityFlags(c)|FL_DUCKING);
}
void SeatPhysicsRestore(int c){
    for(int i=0;i<sizeof(seatPhysicsProps);i++)SetEntProp(c,Prop_Send,seatPhysicsProps[i],seatPhysicsSaved[c][i]);
    SetEntityFlags(c,(GetEntityFlags(c)&~FL_DUCKING)|seatDuckFlag[c]);
}

void SeatModel(int c,char[] path,int length){Format(path,length,"models/casino_seats/v2/%s.mdl",seatClasses[view_as<int>(TF2_GetPlayerClass(c))]);}
void SeatsInit(){
    float p[3],origin[3],mins[3]={-24.0,-24.0,0.0},maxs[3]={24.0,24.0,82.0};
    if(!SeatPlayerOverlap(p,origin,mins,maxs))SetFailState("Seat overlap selftest failed");
    p[2]=84.0;if(SeatPlayerOverlap(p,origin,mins,maxs))SetFailState("Seat head clearance selftest failed");
    p[2]=0.0;p[0]=48.0;if(SeatPlayerOverlap(p,origin,mins,maxs))SetFailState("Seat adjacent clearance selftest failed");
    p[0]=0.0;maxs[2]=62.0;p[2]=64.0;
    if(SeatPlayerOverlap(p,origin,mins,maxs))SetFailState("Seat crouched head clearance selftest failed");
    seatPushaway=FindConVar("tf_avoidteammates_pushaway");
    seatCrosshair=CreateHudSynchronizer();
    HookEvent("player_death",SeatReset,EventHookMode_Pre);HookEvent("player_spawn",SeatReset,EventHookMode_Pre);
    HookEvent("player_team",SeatReset,EventHookMode_Pre);HookEvent("player_changeclass",SeatReset,EventHookMode_Pre);
    AddCommandListener(SeatBlock,"taunt");AddCommandListener(SeatBlock,"+taunt");
}
bool SeatsPrecache(){
    if(!PrecacheModel(CHAIR_MODEL,true))return false;
    if(!PrecacheModel(SEAT_CAMERA_RIG,true)||!PrecacheModel(SEAT_CAMERA_MODEL,true))return false;
    char path[PLATFORM_MAX_PATH];
    for(int i=1;i<=9;i++){
        Format(path,sizeof(path),"models/casino_seats/v2/%s.mdl",seatClasses[i]);
        if(!FileExists(path,true)||!PrecacheModel(path,true))return false;
    }
    return true;
}
public void SeatReset(Event e,const char[] name,bool broadcast){int c=GetClientOfUserId(e.GetInt("userid"));if(c>0){seatDiscard[c]=true;SeatStop(c,false);}}
public Action SeatBlock(int c,const char[] cmd,int argc){return c>0&&seatSlot[c]?Plugin_Handled:Plugin_Continue;}
bool CreateChair(int s){
    float p[3],end[3];WorldPoint(s,50.0,0.0,-BASE_HEIGHT+50.0,p);end=p;end[2]-=100.0;
    Handle tr=TR_TraceRayFilterEx(p,end,MASK_SOLID,RayType_EndPoint,TraceWorld);
    if(!TR_DidHit(tr)||TR_StartSolid(tr)||TR_AllSolid(tr)){delete tr;return false;}
    float normal[3];TR_GetEndPosition(p,tr);TR_GetPlaneNormal(tr,normal);delete tr;if(normal[2]<0.7)return false;
    if(FloatAbs(p[2]-machines[s].origin[2])>48.0)return false;
    machines[s].chairOrigin=p;machines[s].chair=Prop(CHAIR_MODEL,true);
    int e=Entity(machines[s].chair);if(e==-1)return false;
    float a[3];a[1]=machines[s].yaw+90.0;TeleportEntity(e,p,a,NULL_VECTOR);return true;
}
public bool SeatTrace(int e,int mask,any c){
    if(e>0&&e<=MaxClients)return false;
    if(c<0)for(int s=0;s<COUNT;s++)if(e==Entity(machines[s].chair))return false;
    return true;
}
bool SeatClear(int c,const float p[3],bool mounting=false){
    float mins[3]={-24.0,-24.0,0.0},maxs[3]={24.0,24.0,82.0};
    if(mounting)mins[2]=48.0;
    Handle tr=TR_TraceHullFilterEx(p,p,mins,maxs,MASK_PLAYERSOLID,SeatTrace,mounting?-c:c);
    bool clear=!TR_DidHit(tr)&&!TR_StartSolid(tr);delete tr;return clear;
}
bool SeatUse(int c){
    float eye[3],a[3],direction[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,a);GetAngleVectors(a,direction,NULL_VECTOR,NULL_VECTOR);
    float end[3];for(int i=0;i<3;i++)end[i]=eye[i]+direction[i]*120.0;
    Handle tr=TR_TraceRayFilterEx(eye,end,MASK_SOLID,RayType_EndPoint,SeatAimTrace,c);
    int hit=TR_DidHit(tr)?TR_GetEntityIndex(tr):-1;delete tr;
    int best=-1;for(int s=0;s<COUNT;s++)if(hit>MaxClients&&hit==Entity(machines[s].chair)){best=s;break;}
    if(best==-1)return false;
    for(int other=1;other<=MaxClients;other++)if(seatSlot[other]==best+1){PrintToChat(c,"[타워슬롯] 이미 앉아 있는 의자입니다.");return true;}
    SeatBegin(c,best);return true;
}
public bool SeatAimTrace(int e,int mask,any c){return e==0||e>MaxClients;}
public bool SeatVerifyTrace(int e,int mask,any target){return e==target;}
public Action SeatVerify(int c,int args){
    if(!ready){ReplyToCommand(c,"Seat verify FAIL: not ready");return Plugin_Handled;}
    int ref=Prop(CHAIR_MODEL,true),e=Entity(ref);
    if(e==-1){ReplyToCommand(c,"Seat verify FAIL: prop creation");return Plugin_Handled;}
    int hits;
    for(int i=0;i<3;i++){
        float start[3],end[3];start[0]=100.0;end[0]=-100.0;start[2]=end[2]=i==0?5.0:(i==1?34.0:55.0);
        Handle tr=TR_TraceRayFilterEx(start,end,MASK_SOLID,RayType_EndPoint,SeatVerifyTrace,e);
        if(TR_DidHit(tr)&&TR_GetEntityIndex(tr)==e)hits++;delete tr;
    }
    int solid=GetEntProp(e,Prop_Send,"m_nSolidType");RemoveEntity(e);
    int eyeChecks;bool eyeValid=true;
    for(int p=1;p<=MaxClients;p++)if(IsClientInGame(p)){
        if(!HasEntProp(p,Prop_Data,"m_vecViewOffset")){eyeValid=false;continue;}
        for(int i=0;i<sizeof(seatPhysicsProps);i++)if(!HasEntProp(p,Prop_Send,seatPhysicsProps[i]))eyeValid=false;
        float eye[3];GetEntPropVector(p,Prop_Data,"m_vecViewOffset",eye);eyeChecks++;
    }
    bool settlement=true;
    for(int i=0;i<9;i++){
        int bank=17,reward=SettleReward(i,bank);
        if(i==0){if(bank!=0||reward!=17)settlement=false;}
        else if(bank!=17||reward!=payout[i])settlement=false;
    }
    bool cameraValid=SeatCameraVerify();
    for(int s=0;s<COUNT;s++)if(Entity(machines[s].body)==-1){
        Celebrate(s,0);bool effects=true;
        for(int i=0;i<WIN_FX_COUNT;i++)if(i%4!=3&&Entity(machines[s].celebration[i])==-1)effects=false;
        UpdateCelebration(s,machines[s].celebrationRepeat);
        for(int i=0;i<WIN_FX_COUNT;i++)if(Entity(machines[s].celebration[i])==-1)effects=false;
        ClearCelebration(s);
        for(int i=0;i<WIN_FX_COUNT;i++)if(Entity(machines[s].celebration[i])!=-1)effects=false;
        Celebrate(s,1);
        if(Entity(machines[s].celebration[0])==-1||Entity(machines[s].celebration[1])==-1)effects=false;
        UpdateCelebration(s,machines[s].celebrationCoinUntil);
        if(Entity(machines[s].celebration[1])!=-1||Entity(machines[s].celebration[0])==-1)effects=false;
        UpdateCelebration(s,machines[s].celebrationUntil);
        for(int i=0;i<WIN_FX_COUNT;i++)if(Entity(machines[s].celebration[i])!=-1)effects=false;
        if(!effects)cameraValid=false;
        LogMessage("Slot effects verify %s: jackpot creation and cleanup",effects?"PASS":"FAIL");break;
    }
    int expected[]={0,275,240,322,239,178,228,237,243,314};
    for(int cls=1;cls<=9;cls++){
        char model[PLATFORM_MAX_PATH];Format(model,sizeof(model),"models/casino_seats/v2/%s.mdl",seatClasses[cls]);
        int pose=Prop(model),entity=Entity(pose);if(entity==-1){LogError("Seat pose verify: creation failed class=%d",cls);continue;}
        SetEntityRenderMode(entity,RENDER_NONE);
        SetVariantString("casino_sitting_idle");AcceptEntityInput(entity,"SetDefaultAnimation");Animate(pose,"casino_sitting_idle");
        DataPack pack;CreateDataTimer(5.0,SeatVerifyPose,pack,TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(pose);pack.WriteCell(expected[cls]);pack.WriteCell(cls);
    }
    int sharedTest=9;
    if(SettleReward(1,sharedTest)!=payout[1]||sharedTest!=9)settlement=false;
    if(SettleReward(0,sharedTest)!=9||SettleReward(0,sharedTest)!=0)settlement=false;
    ReplyToCommand(c,"Seat verify %s: solid=%d rays=%d/3 jackpot_settlement=%d eye_checks=%d eye_valid=%d camera_rig=%d",hits==3&&solid==6&&settlement&&eyeValid&&cameraValid?"PASS":"FAIL",solid,hits,settlement,eyeChecks,eyeValid,cameraValid);
    return Plugin_Handled;
}
public Action SeatVerifyPose(Handle timer,DataPack pack){
    pack.Reset();int e=Entity(pack.ReadCell()),expected=pack.ReadCell(),cls=pack.ReadCell();
    if(e==-1)return Plugin_Stop;
    int actual=GetEntProp(e,Prop_Send,"m_nSequence");float cycle=GetEntPropFloat(e,Prop_Send,"m_flCycle");
    if(actual!=expected||cycle<=0.0)LogError("Seat pose verify FAIL class=%d expected=%d actual=%d cycle=%f",cls,expected,actual,cycle);
    else LogMessage("Seat pose verify PASS class=%d sequence=%d cycle=%f",cls,actual,cycle);
    RemoveEntity(e);return Plugin_Stop;
}
bool SeatBodyCreate(int c){
    seatBody[c]=SeatClone(c,seatOldModel[c],seatSkin[c],seatGroups[c]);
    return Entity(seatBody[c])!=-1;
}
void SeatBegin(int c,int s){
    int cls=view_as<int>(TF2_GetPlayerClass(c));
    if(cls<1||cls>9||seatSlot[c]||TF2_IsPlayerInCondition(c,TFCond_Taunting)||TF2_IsPlayerInCondition(c,TFCond_Cloaked)
       ||TF2_IsPlayerInCondition(c,TFCond_Disguised)||TF2_IsPlayerInCondition(c,TFCond_Disguising)
       ||GetEntityMoveType(c)!=MOVETYPE_WALK||GetEntProp(c,Prop_Send,"m_nForceTauntCam")!=0){PrintToChat(c,"[타워슬롯] 다른 도발·변신·은폐를 해제한 뒤 앉으세요.");return;}
    float p[3];p=machines[s].chairOrigin;
    if(!SeatClear(c,p,true)){PrintToChat(c,"[타워슬롯] 의자 위 몸통·머리 공간이 막혀 있습니다.");return;}
    char model[PLATFORM_MAX_PATH];SeatModel(c,model,sizeof(model));if(!IsModelPrecached(model))return;
    if(!HasEntProp(c,Prop_Data,"m_vecViewOffset")){PrintToChat(c,"[타워슬롯] 시점 속성을 찾지 못했습니다.");return;}
    int view=GetEntPropEnt(c,Prop_Data,"m_hViewEntity");
    if(view>0&&view!=c){PrintToChat(c,"[타워슬롯] 다른 카메라 모드를 먼저 해제하세요.");return;}
    GetEntPropString(c,Prop_Send,"m_iszCustomModel",seatOldModel[c],sizeof(seatOldModel[]));
    seatAnimations[c]=GetEntProp(c,Prop_Send,"m_bUseClassAnimations");seatFx[c]=GetEntityRenderFx(c);
    seatSkin[c]=GetEntProp(c,Prop_Send,"m_nSkin");seatGroups[c]=GetEntProp(c,Prop_Send,"m_nBody");
    GetEntPropVector(c,Prop_Data,"m_vecViewOffset",seatOldEye[c]);GetClientAbsOrigin(c,seatEntry[c]);seatMove[c]=GetEntityMoveType(c);
    SeatPhysicsSave(c);
    seatSlot[c]=s+1;seatBody[c]=INVALID_ENT_REFERENCE;seatThird[c]=false;
    SeatViewSave(c);
    if(!SeatStoreWeapons(c)){SeatStop(c,false);PrintToChat(c,"[타워슬롯] 무기 보관 실패로 탑승을 취소했습니다.");return;}
    float angles[3],zero[3];angles[1]=machines[s].yaw+180.0;TeleportEntity(c,p,angles,zero);
    if(!SeatViewStart(c,model,p,angles)){SeatStop(c,false);PrintToChat(c,"[타워슬롯] 탑승 카메라 생성 실패.");return;}
    SetEntityMoveType(c,MOVETYPE_NONE);SetEntProp(c,Prop_Send,"m_nForceTauntCam",0);
    SeatPhysicsHold(c);
    if(seatPushaway!=null&&!IsFakeClient(c))SendConVarValue(c,seatPushaway,"0");
    CasinoHint(c,"Ctrl: 내리기 · 휠 클릭: 1/3인칭\nE: 버튼/레버 · 스페이스: 레버");
    LogMessage("Seat enter userid=%d class=%d slot=%d",GetClientUserId(c),cls,s);
}
bool SeatPlayerOverlap(const float p[3],const float origin[3],const float mins[3],const float maxs[3]){
    return p[0]+24.0>origin[0]+mins[0]&&p[0]-24.0<origin[0]+maxs[0]
        &&p[1]+24.0>origin[1]+mins[1]&&p[1]-24.0<origin[1]+maxs[1]
        &&p[2]+82.0>origin[2]+mins[2]&&p[2]<origin[2]+maxs[2];
}
bool SeatExitClear(int c,float point[3]){
    float base[3];base=point;
    for(int step=0;step<=6;step++){
        point=base;point[2]+=float(step)*8.0;
        if(!SeatClear(c,point))continue;
        // Raise above overlapping players, rechecking the complete hull against ceilings.
        for(int pass=0;pass<=MaxClients;pass++){
            int blocker;float top=point[2];
            for(int other=1;other<=MaxClients;other++)if(other!=c&&Player(other)){
                float origin[3],mins[3],maxs[3];GetClientAbsOrigin(other,origin);
                GetClientMins(other,mins);GetClientMaxs(other,maxs);
                if(SeatPlayerOverlap(point,origin,mins,maxs)){
                    blocker=other;if(origin[2]+maxs[2]+2.0>top)top=origin[2]+maxs[2]+2.0;
                }
            }
            if(!blocker)return true;
            point[2]=top;if(!SeatClear(c,point))break;
        }
    }
    return false;
}
bool SeatExitPoint(int c,int s,float point[3]){
    for(int i=0;i<8;i++){
        float a=DegToRad(machines[s].yaw+float(i)*45.0),start[3],end[3];start=machines[s].chairOrigin;
        start[0]+=Cosine(a)*65.0;start[1]+=Sine(a)*65.0;start[2]+=50.0;end=start;end[2]-=100.0;
        Handle tr=TR_TraceRayFilterEx(start,end,MASK_PLAYERSOLID,RayType_EndPoint,SeatTrace,c);
        if(!TR_DidHit(tr)||TR_StartSolid(tr)||TR_AllSolid(tr)){delete tr;continue;}float normal[3];TR_GetEndPosition(point,tr);TR_GetPlaneNormal(tr,normal);delete tr;
        if(FloatAbs(point[2]-machines[s].chairOrigin[2])>48.0)continue;
        point[2]+=2.0;if(normal[2]>=0.7&&SeatExitClear(c,point))return true;
    }
    point=seatEntry[c];point[2]+=2.0;return SeatExitClear(c,point);
}
void SeatStop(int c,bool requested){
    if(c<1||c>MaxClients||!seatSlot[c])return;
    int s=seatSlot[c]-1;
    if(requested&&machines[s].busy){PrintToChat(c,"[타워슬롯] 회전 결과가 나온 뒤 내릴 수 있습니다.");return;}
    float point[3];bool place=Player(c)&&SeatExitPoint(c,s,point);
    if(requested&&!place){PrintToChat(c,"[타워슬롯] 하차할 공간이 없습니다.");return;}
    seatSlot[c]=0;
    if(!IsClientInGame(c))return;
    if(seatPushaway!=null&&!IsFakeClient(c)){
        char value[16];seatPushaway.GetString(value,sizeof(value));SendConVarValue(c,seatPushaway,value);
    }
    SeatViewStop(c);
    char current[PLATFORM_MAX_PATH];GetEntPropString(c,Prop_Send,"m_iszCustomModel",current,sizeof(current));
    if(StrEqual(current,SEAT_CAMERA_RIG)){
        SetVariantString(seatOldModel[c]);AcceptEntityInput(c,"SetCustomModel");SetEntProp(c,Prop_Send,"m_bUseClassAnimations",seatAnimations[c]);
        SetEntProp(c,Prop_Send,"m_nSkin",seatSkin[c]);SetEntProp(c,Prop_Send,"m_nBody",seatGroups[c]);
        SeatViewRestoreModel(c);
    }
    int body=Entity(seatBody[c]);seatBody[c]=INVALID_ENT_REFERENCE;if(body!=-1)RemoveEntity(body);
    if(GetEntityRenderFx(c)==RENDERFX_FADE_FAST)SetEntityRenderFx(c,seatFx[c]);
    SetEntProp(c,Prop_Send,"m_nForceTauntCam",0);SetEntPropVector(c,Prop_Data,"m_vecViewOffset",seatOldEye[c]);
    if(GetEntityMoveType(c)==MOVETYPE_NONE)SetEntityMoveType(c,seatMove[c]);
    if(place){float zero[3];TeleportEntity(c,point,NULL_VECTOR,zero);}
    SeatPhysicsRestore(c);
    LogMessage("Seat exit userid=%d slot=%d",GetClientUserId(c),s);
}
void SeatsFrame(){
    for(int c=1;c<=MaxClients;c++)if(seatSlot[c]){
        if(!Player(c)||Entity(machines[seatSlot[c]-1].chair)==-1){SeatStop(c,false);continue;}
        if(!SeatStoreWeapons(c)){SeatStop(c,false);continue;}
        float origin[3],zero[3];GetClientAbsOrigin(c,origin);
        // Preserve mouse look; repair only displacement from the fixed seat anchor.
        if(GetVectorDistance(origin,machines[seatSlot[c]-1].chairOrigin,true)>0.0001){
            int parity=GetEntProp(c,Prop_Send,"m_ubInterpolationFrame");
            TeleportEntity(c,machines[seatSlot[c]-1].chairOrigin,NULL_VECTOR,zero);
            SetEntProp(c,Prop_Send,"m_ubInterpolationFrame",parity);
        }
        SetEntityMoveType(c,MOVETYPE_NONE);
        SeatPhysicsHold(c);
        if(!SeatViewUpdate(c)){SeatStop(c,false);continue;}
        float eye[3];eye[2]=seatEyes[view_as<int>(TF2_GetPlayerClass(c))];SetEntPropVector(c,Prop_Data,"m_vecViewOffset",eye);
    }
}

#include "tower_slots_camera.inc"
