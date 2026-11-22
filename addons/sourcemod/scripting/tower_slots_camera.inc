// Same local-animstate camera rig as farming_walker; visible class body stays fixed to the chair.
int seatCamera[MAXPLAYERS+1],seatVisual[MAXPLAYERS+1];
char seatViewProps[][]={"m_bForceLocalPlayerDraw","m_bCustomModelVisibleToSelf","m_bDrawViewmodel","m_bCustomModelRotates","m_bCustomModelRotationSet","m_bClientSideAnimation","m_nSequence","m_nHitboxSet"};
int seatViewSaved[MAXPLAYERS+1][8];
float seatOffset[MAXPLAYERS+1][3],seatRotation[MAXPLAYERS+1][3],seatCycle[MAXPLAYERS+1],seatPlayback[MAXPLAYERS+1];
float seatViewPosition[MAXPLAYERS+1][3],seatCrosshairAt[MAXPLAYERS+1];
RenderMode seatRender[MAXPLAYERS+1];
ArrayList seatCosmetics[MAXPLAYERS+1];
ArrayList seatWeapons[MAXPLAYERS+1];
int seatWeaponActive[MAXPLAYERS+1],seatClass[MAXPLAYERS+1],seatTeam[MAXPLAYERS+1];

void SeatViewSave(int c){
    seatCamera[c]=seatVisual[c]=INVALID_ENT_REFERENCE;
    for(int i=0;i<sizeof(seatViewProps);i++)seatViewSaved[c][i]=GetEntProp(c,Prop_Send,seatViewProps[i]);
    GetEntPropVector(c,Prop_Send,"m_vecCustomModelOffset",seatOffset[c]);
    GetEntPropVector(c,Prop_Send,"m_angCustomModelRotation",seatRotation[c]);
    seatCycle[c]=GetEntPropFloat(c,Prop_Send,"m_flCycle");seatPlayback[c]=GetEntPropFloat(c,Prop_Send,"m_flPlaybackRate");
    seatRender[c]=GetEntityRenderMode(c);seatCosmetics[c]=new ArrayList(3);
    seatWeapons[c]=new ArrayList(4);seatDiscard[c]=false;
    seatClass[c]=view_as<int>(TF2_GetPlayerClass(c));seatTeam[c]=GetClientTeam(c);
    int active=GetEntPropEnt(c,Prop_Send,"m_hActiveWeapon");seatWeaponActive[c]=active>MaxClients?EntIndexToEntRef(active):INVALID_ENT_REFERENCE;
    seatCrosshairAt[c]=0.0;
}
public Action SeatVisualTransmit(int e,int viewer){
    if(viewer<1||viewer>MaxClients||!seatSlot[viewer]||seatThird[viewer])return Plugin_Continue;
    if(e==Entity(seatVisual[viewer])||e==Entity(seatBody[viewer]))return Plugin_Handled;
    if(seatCosmetics[viewer]!=null)for(int i=0;i<seatCosmetics[viewer].Length;i++){
        int row[3];seatCosmetics[viewer].GetArray(i,row);if(e==Entity(row[2]))return Plugin_Handled;
    }
    return Plugin_Continue;
}
int SeatClone(int c,const char[] model,int skin,int body){
    int ref=Prop(model),e=Entity(ref),parent=Entity(seatVisual[c]);if(e==-1||parent==-1){if(e!=-1)RemoveEntity(e);return INVALID_ENT_REFERENCE;}
    SetEntProp(e,Prop_Send,"m_nSkin",skin);SetEntProp(e,Prop_Send,"m_nBody",body);
    // IsFollowingEntity requires MOVETYPE_NONE as well as EF_BONEMERGE.
    SetEntityMoveType(e,MOVETYPE_NONE);
    SetVariantString("!activator");
    if(!AcceptEntityInput(e,"SetParent",parent)||GetEntPropEnt(e,Prop_Data,"m_hMoveParent")!=parent){RemoveEntity(e);return INVALID_ENT_REFERENCE;}
    SetEntProp(e,Prop_Send,"m_fEffects",1|512);
    float zero[3];TeleportEntity(e,zero,zero,NULL_VECTOR);
    SDKHook(e,SDKHook_SetTransmit,SeatVisualTransmit);return ref;
}
void SeatAttachCosmetic(int c,int e){
    if(e<=MaxClients||!IsValidEntity(e))return;
    int ref=EntIndexToEntRef(e);if(seatCosmetics[c].FindValue(ref)!=-1)return;
    char model[PLATFORM_MAX_PATH];GetEntPropString(e,Prop_Data,"m_ModelName",model,sizeof(model));
    int clone=SeatClone(c,model,GetEntProp(e,Prop_Send,"m_nSkin"),GetEntProp(e,Prop_Send,"m_nBody"));
    if(Entity(clone)==-1)return;
    int row[3];row[0]=ref;row[1]=view_as<int>(GetEntityRenderMode(e));row[2]=clone;
    seatCosmetics[c].PushArray(row);SetEntityRenderMode(e,RENDER_NONE);
}
bool SeatViewStart(int c,const char[] model,const float p[3],const float angles[3]){
    SetVariantString(SEAT_CAMERA_RIG);if(!AcceptEntityInput(c,"SetCustomModelWithClassAnimations"))return false;
    float zero[3],offset[3];offset[2]=seatEyes[view_as<int>(TF2_GetPlayerClass(c))]-80.0;
    SetEntPropVector(c,Prop_Send,"m_vecCustomModelOffset",offset);
    SetEntProp(c,Prop_Send,"m_bCustomModelRotates",1);SetEntProp(c,Prop_Send,"m_bCustomModelRotationSet",0);
    SetEntProp(c,Prop_Send,"m_nSequence",0);SetEntProp(c,Prop_Send,"m_bClientSideAnimation",1);
    SetEntPropFloat(c,Prop_Send,"m_flCycle",0.0);SetEntPropFloat(c,Prop_Send,"m_flPlaybackRate",1.0);
    SetEntProp(c,Prop_Send,"m_bDrawViewmodel",0);SetEntProp(c,Prop_Send,"m_bForceLocalPlayerDraw",1);
    SetEntProp(c,Prop_Send,"m_bCustomModelVisibleToSelf",0);SetEntityRenderMode(c,RENDER_NONE);
    seatVisual[c]=Prop(model);int visual=Entity(seatVisual[c]);if(visual==-1)return false;
    SetEntProp(visual,Prop_Send,"m_nSkin",seatSkin[c]);
    SetEntProp(visual,Prop_Send,"m_nBody",seatGroups[c]);SetEntityMoveType(visual,MOVETYPE_NONE);
    TeleportEntity(visual,p,angles,NULL_VECTOR);
    SetVariantString("casino_sitting_idle");AcceptEntityInput(visual,"SetDefaultAnimation");
    Animate(seatVisual[c],"casino_sitting_idle");
    SDKHook(visual,SDKHook_SetTransmit,SeatVisualTransmit);
    if(seatOldModel[c][0]){
        if(!SeatBodyCreate(c))return false;
        SetEntityRenderFx(visual,RENDERFX_FADE_FAST);
    }
    int e=-1;
    while((e=FindEntityByClassname(e,"tf_wearable"))!=-1)
        if(GetEntPropEnt(e,Prop_Send,"m_hOwnerEntity")==c)SeatAttachCosmetic(c,e);
    seatCamera[c]=Prop(SEAT_CAMERA_MODEL);int camera=Entity(seatCamera[c]);if(camera==-1)return false;
    SetEntityMoveType(camera,MOVETYPE_NONE);SetEntPropEnt(camera,Prop_Send,"m_hOwnerEntity",c);
    SetEntityRenderMode(camera,RENDER_TRANSCOLOR);SetEntityRenderColor(camera,255,255,255,0);
    SetEntProp(camera,Prop_Send,"m_fEffects",512);
    SetVariantString("!activator");if(!AcceptEntityInput(camera,"SetParent",c))return false;
    int attachment=LookupEntityAttachment(c,"local_camera");if(attachment<=0)return false;
    SetVariantString("local_camera");if(!AcceptEntityInput(camera,"SetParentAttachment",c)
       ||GetEntProp(camera,Prop_Send,"m_iParentAttachment")!=attachment)return false;
    TeleportEntity(camera,zero,zero,NULL_VECTOR);
    if(!SeatViewUpdate(c))return false;
#if !defined CASINO_NATIVE_FIRSTPERSON
    SetEntPropEnt(c,Prop_Data,"m_hViewEntity",camera);SetClientViewEntity(c,camera);
#endif
    return true;
}
public bool SeatCameraTrace(int e,int mask,any c){
    if(e>0&&e<=MaxClients)return false;
    if(e==Entity(seatVisual[c])||e==Entity(seatCamera[c])||e==Entity(seatBody[c]))return false;
    return e!=Entity(machines[seatSlot[c]-1].chair);
}
bool SeatViewUpdate(int c){
    int camera=Entity(seatCamera[c]);if(camera==-1||Entity(seatVisual[c])==-1)return false;
    SetEntProp(c,Prop_Send,"m_bCustomModelVisibleToSelf",seatThird[c]?1:0);
    float origin[3],angles[3],look[3],head[3],pos[3];
    origin=machines[seatSlot[c]-1].chairOrigin;GetClientEyeAngles(c,angles);GetAngleVectors(angles,look,NULL_VECTOR,NULL_VECTOR);
    head=origin;head[2]+=seatEyes[view_as<int>(TF2_GetPlayerClass(c))];pos=head;
#if defined CASINO_NATIVE_FIRSTPERSON
    int view=seatThird[c]?camera:c;
    float eyeOffset[3];eyeOffset[2]=seatEyes[view_as<int>(TF2_GetPlayerClass(c))];SetEntPropVector(c,Prop_Data,"m_vecViewOffset",eyeOffset);
    if(GetEntPropEnt(c,Prop_Data,"m_hViewEntity")!=view){SetEntPropEnt(c,Prop_Data,"m_hViewEntity",view);SetClientViewEntity(c,view);}
#endif
    if(seatThird[c])for(int i=0;i<3;i++)pos[i]-=look[i]*85.0;
    float mins[3]={-3.0,-3.0,-3.0},maxs[3]={3.0,3.0,3.0};
    Handle tr=TR_TraceHullFilterEx(head,pos,mins,maxs,MASK_SOLID,SeatCameraTrace,c);
    if(TR_StartSolid(tr)||TR_AllSolid(tr))pos=head;
    else if(TR_DidHit(tr)){float f=TR_GetFraction(tr)-0.01;if(f<0.0)f=0.0;for(int i=0;i<3;i++)pos[i]=head[i]+(pos[i]-head[i])*f;}
    delete tr;seatViewPosition[c]=pos;
    // Constant local offset in free space; only wall clipping changes arm length.
    float local[3];local[0]=-GetVectorDistance(head,pos);
    int parity=GetEntProp(camera,Prop_Send,"m_ubInterpolationFrame");
    TeleportEntity(camera,local,NULL_VECTOR,NULL_VECTOR);SetEntProp(camera,Prop_Send,"m_ubInterpolationFrame",parity);
    if(!IsFakeClient(c)&&GetGameTime()>=seatCrosshairAt[c]){
        seatCrosshairAt[c]=GetGameTime()+0.1;
        SetHudTextParams(-1.0,0.49,0.25,150,255,170,255,0,0.0,0.0,0.0);ShowSyncHudText(c,seatCrosshair,"+");
    }
    return true;
}
void SeatAim(int c,float eye[3],float angles[3]){
    GetClientEyeAngles(c,angles);
    if(seatSlot[c]&&SeatViewUpdate(c))eye=seatViewPosition[c];else GetClientEyePosition(c,eye);
}
void SeatViewStop(int c){
    int camera=Entity(seatCamera[c]),visual=Entity(seatVisual[c]);
    if(camera!=-1&&GetEntPropEnt(c,Prop_Data,"m_hViewEntity")==camera){SetEntPropEnt(c,Prop_Data,"m_hViewEntity",c);SetClientViewEntity(c,c);}
    if(seatCosmetics[c]!=null){
        for(int i=0;i<seatCosmetics[c].Length;i++){
            int row[3];seatCosmetics[c].GetArray(i,row);int e=Entity(row[0]),clone=Entity(row[2]);
            if(e!=-1&&GetEntityRenderMode(e)==RENDER_NONE)SetEntityRenderMode(e,view_as<RenderMode>(row[1]));
            if(clone!=-1)RemoveEntity(clone);
        }
        delete seatCosmetics[c];
    }
    if(camera!=-1)RemoveEntity(camera);if(visual!=-1)RemoveEntity(visual);
    seatCamera[c]=seatVisual[c]=INVALID_ENT_REFERENCE;
    SetEntityRenderMode(c,seatRender[c]);
    SeatReturnWeapons(c,!seatDiscard[c]&&Player(c)&&view_as<int>(TF2_GetPlayerClass(c))==seatClass[c]&&GetClientTeam(c)==seatTeam[c]);
    if(!IsFakeClient(c))ClearSyncHud(c,seatCrosshair);
}
void SeatViewRestoreModel(int c){
    for(int i=0;i<sizeof(seatViewProps);i++)SetEntProp(c,Prop_Send,seatViewProps[i],seatViewSaved[c][i]);
    SetEntPropVector(c,Prop_Send,"m_vecCustomModelOffset",seatOffset[c]);SetEntPropVector(c,Prop_Send,"m_angCustomModelRotation",seatRotation[c]);
    SetEntPropFloat(c,Prop_Send,"m_flCycle",seatCycle[c]);SetEntPropFloat(c,Prop_Send,"m_flPlaybackRate",seatPlayback[c]);
}
bool SeatCameraVerify(){
    int ref=Prop(SEAT_CAMERA_RIG),e=Entity(ref);if(e==-1)return false;
    bool ok=LookupEntityAttachment(e,"local_camera")>0;RemoveEntity(e);
    // Slot zero is never a player: exercise the same clone path without mounting anyone.
    int saved=seatVisual[0];seatVisual[0]=Prop("models/casino_seats/v2/scout.mdl");
    int parent=Entity(seatVisual[0]),copy=SeatClone(0,"models/casino_seats/v2/scout.mdl",0,0),child=Entity(copy);
    bool merge=parent!=-1&&child!=-1;
    if(merge)merge=GetEntityMoveType(child)==MOVETYPE_NONE
        &&GetEntPropEnt(child,Prop_Data,"m_hMoveParent")==parent
        &&(GetEntProp(child,Prop_Send,"m_fEffects")&1)!=0;
    if(child!=-1)RemoveEntity(child);if(parent!=-1)RemoveEntity(parent);seatVisual[0]=saved;
    for(int player=1;player<=MaxClients;player++)if(SeatCameraTrace(player,MASK_SOLID,0))ok=false;
    LogMessage("Seat clone verify %s: bone-merge follow requirements",merge?"PASS":"FAIL");
    if(!merge)ok=false;
    // A centered first-person camera must remain at local zero at every angle.
    for(int pitch=-80;pitch<=80;pitch+=40)for(int yaw=-180;yaw<=180;yaw+=45){
        float a[3],look[3],right[3],up[3],delta[3]={24.0,-18.0,-70.0},local[3],world[3];
        a[0]=float(pitch);a[1]=float(yaw);GetAngleVectors(a,look,right,up);
        local[0]=GetVectorDotProduct(delta,look);local[1]=-GetVectorDotProduct(delta,right);local[2]=GetVectorDotProduct(delta,up);
        for(int i=0;i<3;i++)world[i]=local[0]*look[i]-local[1]*right[i]+local[2]*up[i];
        if(GetVectorDistance(delta,world)>0.001)ok=false;
        float head[3]={0.0,0.0,80.0},pos[3];pos=head;
        if(GetVectorDistance(head,pos)!=0.0)ok=false;
        for(int i=0;i<3;i++)pos[i]=head[i]-look[i]*85.0;
        if(FloatAbs(GetVectorDistance(head,pos)-85.0)>0.001)ok=false;
    }
    return ok;
}


bool SeatStoreWeapons(int c)
{
    // Remove from inventory but retain the original entities and item attributes.
    int slots=GetEntPropArraySize(c,Prop_Send,"m_hMyWeapons");
    for (int i;i<slots;i++)
    {
        int weapon=GetEntPropEnt(c,Prop_Send,"m_hMyWeapons",i);
        if (weapon<=MaxClients || !IsValidEntity(weapon)) continue;
        int entry[4]; entry[0]=EntIndexToEntRef(weapon);
        entry[1]=GetEntProp(weapon,Prop_Send,"m_iClip1");
        entry[2]=GetEntProp(weapon,Prop_Send,"m_iClip2");
        entry[3]=GetEntProp(weapon,Prop_Send,"m_fEffects");
        if (!RemovePlayerItem(c,weapon)) return false;
        seatWeapons[c].PushArray(entry);
        weapon=EntRefToEntIndex(entry[0]);
        if (weapon<=MaxClients || !IsValidEntity(weapon)) return false;
        SetEntProp(weapon,Prop_Send,"m_fEffects",entry[3] | 32);
        SDKHook(weapon,SDKHook_Touch,SeatBlockPickup);
    }
    return GetEntPropEnt(c,Prop_Send,"m_hActiveWeapon")<=MaxClients;
}
public Action SeatBlockPickup(int weapon,int other) { return Plugin_Handled; }
void SeatReturnWeapons(int c,bool restore)
{
    if (seatWeapons[c]==null) return;
    int ammo[64],count;
    if (restore)
    {
        count=GetEntPropArraySize(c,Prop_Send,"m_iAmmo");
        if (count>sizeof(ammo)) { LogError("Ammo array exceeds restore capacity"); restore=false; count=0; }
        for (int i;i<count;i++) ammo[i]=GetEntProp(c,Prop_Send,"m_iAmmo",_,i);
    }
    for (int i;i<seatWeapons[c].Length;i++)
    {
        int entry[4]; seatWeapons[c].GetArray(i,entry);
        int weapon=EntRefToEntIndex(entry[0]);
        if (weapon<=MaxClients || !IsValidEntity(weapon)) continue;
        SDKUnhook(weapon,SDKHook_Touch,SeatBlockPickup);
        int owner=GetEntPropEnt(weapon,Prop_Send,"m_hOwnerEntity");
        if (owner>0 && owner!=c) { LogError("Stored weapon changed owner: %d",weapon); continue; }
        if (!restore) { RemoveEntity(weapon); continue; }
        EquipPlayerWeapon(c,weapon);
        weapon=EntRefToEntIndex(entry[0]);
        if (weapon<=MaxClients || !IsValidEntity(weapon) || GetEntPropEnt(weapon,Prop_Send,"m_hOwnerEntity")!=c)
        { LogError("Stored weapon restore failed for client %d",c); continue; }
        SetEntProp(weapon,Prop_Send,"m_iClip1",entry[1]);
        SetEntProp(weapon,Prop_Send,"m_iClip2",entry[2]);
        SetEntProp(weapon,Prop_Send,"m_fEffects",entry[3]);
    }
    delete seatWeapons[c];
    for (int i;i<count;i++) SetEntProp(c,Prop_Send,"m_iAmmo",ammo[i],_,i);
    int active=EntRefToEntIndex(seatWeaponActive[c]);
    if (restore && active>MaxClients && IsValidEntity(active) && GetEntPropEnt(active,Prop_Send,"m_hOwnerEntity")==c)
    {
        char classname[64]; GetEntityClassname(active,classname,sizeof(classname));
        FakeClientCommand(c,"use %s",classname);
    }
}
