#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
public Plugin myinfo={name="Unified Casino",author="Codex",description="All casino machines and cards; virtual-chip test rules",version="1.3.0"};
bool casinoStarted;
#include "casino_unified/don.inc"
#include "casino_unified/diamond.inc"
#include "casino_unified/extra.inc"
#include "casino_unified/cards.inc"

int CasinoSeatOwner(int c){
    if(c<1||c>MaxClients)return 0;
    if(Don_seatSlot[c])return 1;
    if(Diamond_seatSlot[c])return 2;
    if(Extra_seatSlot[c])return 3;
    if(Cards_seatSlot[c])return 4;
    return 0;
}
public void OnPluginStart(){
    Handle iterator=GetPluginIterator();char file[PLATFORM_MAX_PATH];
    while(MorePlugins(iterator)){
        Handle plugin=ReadPlugin(iterator);if(plugin==GetMyHandle()||GetPluginStatus(plugin)!=Plugin_Running)continue;
        GetPluginFilename(plugin,file,sizeof(file));
        if(StrEqual(file,"double_nothing_test.smx")||StrEqual(file,"tower_slots_test.smx")||StrEqual(file,"casino_expansion_test.smx")||StrEqual(file,"casino_cards_test.smx")){
            delete iterator;SetFailState("Unload the four standalone casino plugins before loading casino_unified");return;
        }
    }
    delete iterator;
    casinoStarted=true;
    Don_OnPluginStart();Diamond_OnPluginStart();Extra_OnPluginStart();Cards_OnPluginStart();
}
public void OnMapStart(){Don_OnMapStart();Diamond_OnMapStart();Extra_OnMapStart();Cards_OnMapStart();}
public void OnMapEnd(){Don_OnMapEnd();Diamond_OnMapEnd();Extra_OnMapEnd();Cards_OnMapEnd();}
public void OnPluginEnd(){
    if(!casinoStarted)return;
    Don_donEnding=Diamond_slotEnding=Extra_ending=Cards_ending=true;
    Don_OnPluginEnd();Diamond_OnPluginEnd();Extra_OnPluginEnd();Cards_OnPluginEnd();
}
public void OnClientPutInServer(int c){Don_OnClientPutInServer(c);Diamond_OnClientPutInServer(c);Extra_OnClientPutInServer(c);Cards_OnClientPutInServer(c);}
public void OnClientDisconnect(int c){Don_OnClientDisconnect(c);Diamond_OnClientDisconnect(c);Extra_OnClientDisconnect(c);Cards_OnClientDisconnect(c);}
public void OnGameFrame(){Don_OnGameFrame();Diamond_OnGameFrame();Extra_OnGameFrame();Cards_OnGameFrame();}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float velocity[3],float angles[3],int &weapon){
    int owner=CasinoSeatOwner(c),raw=buttons;Action result=Plugin_Continue;
    if(owner==1)result=Don_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
    else if(owner==2)result=Diamond_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
    else if(owner==3)result=Extra_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
    else if(owner==4)result=Cards_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
    else{
        result=Don_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
        if(result==Plugin_Continue&&!CasinoSeatOwner(c))result=Diamond_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
        if(result==Plugin_Continue&&!CasinoSeatOwner(c))result=Extra_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
        if(result==Plugin_Continue&&!CasinoSeatOwner(c))result=Cards_OnPlayerRunCmd(c,buttons,impulse,velocity,angles,weapon);
    }
    Don_previous[c]=Diamond_previous[c]=Extra_previous[c]=Cards_previous[c]=raw;
    return result;
}
