char shopSessionDir[PLATFORM_MAX_PATH], shopToken[MAXPLAYERS+1][65], shopIdentity[MAXPLAYERS+1][32];
int shopOpened[MAXPLAYERS+1];

void ShopSession_Revoke(int client)
{
    if (!shopToken[client][0]) return;
    char path[PLATFORM_MAX_PATH];
    Format(path,sizeof(path),"%s/%s.json",shopSessionDir,shopToken[client]);
    if (FileExists(path) && !DeleteFile(path)) LogError("Could not revoke shop session file");
    shopToken[client][0]='\0';shopIdentity[client][0]='\0';shopOpened[client]=0;
}

bool ShopSession_Publish(int client)
{
    char path[PLATFORM_MAX_PATH],temp[PLATFORM_MAX_PATH],identity[32];
    if (!Player(client) || !GetClientAuthId(client,AuthId_SteamID64,identity,sizeof(identity),true)
        || !StrEqual(identity,shopIdentity[client]) || GetTime()-shopOpened[client]>=1800) return false;
    Format(path,sizeof(path),"%s/%s.json",shopSessionDir,shopToken[client]);
    Format(temp,sizeof(temp),"%s.new",path);
    File file=OpenFile(temp,"w");if(file==null)return false;
    bool ok=file.WriteLine("{\"steamid\":\"%s\",\"opened\":%d,\"expires\":%d}",identity,shopOpened[client],GetTime()+15);
    delete file;
    // PHP can read a known capability path, but cannot list or alter game grants.
    if(ok)ok=SetFilePermissions(temp,420)&&RenameFile(path,temp);
    if(!ok&&FileExists(temp))DeleteFile(temp);
    return ok;
}

bool ShopSession_Issue(int client)
{
    ShopSession_Revoke(client);
    if (!GetClientAuthId(client,AuthId_SteamID64,shopIdentity[client],sizeof(shopIdentity[]),true)) return false;
    // This is an authentication secret: never use the gameplay PRNG.
    // SourceMod rebases paths to the Linux game directory /home/container/tf.
    File random=OpenFile("../../../dev/urandom","rb");if(random==null)return false;
    char hex[]="0123456789abcdef";bool ok=true;
    for(int i=0;i<32;i++){
        int value;if(!random.ReadInt8(value)){ok=false;break;}
        shopToken[client][i*2]=hex[(value>>4)&15];shopToken[client][i*2+1]=hex[value&15];
    }
    delete random;shopToken[client][64]='\0';shopOpened[client]=GetTime();
    if(!ok||!ShopSession_Publish(client)){ShopSession_Revoke(client);return false;}
    return true;
}

public Action ShopSession_Heartbeat(Handle timer)
{
    for(int c=1;c<=MaxClients;c++)if(shopToken[c][0]&&!ShopSession_Publish(c))ShopSession_Revoke(c);
    return Plugin_Continue;
}

void ShopSession_Start()
{
    BuildPath(Path_SM,shopSessionDir,sizeof(shopSessionDir),"data/bot_trade_shop_sessions");
    // SourcePawn integers are decimal: 457 = Unix 0711; 420 = Unix 0644.
    if(!DirExists(shopSessionDir)&&!CreateDirectory(shopSessionDir,457))SetFailState("Shop game session directory unavailable");
    if(!SetFilePermissions(shopSessionDir,457))SetFailState("Shop game session permissions unavailable");
    DirectoryListing files=OpenDirectory(shopSessionDir);
    if(files!=null){
        char name[96],path[PLATFORM_MAX_PATH];FileType type;
        while(files.GetNext(name,sizeof(name),type)){
            if(type!=FileType_File||strlen(name)!=69||!StrEqual(name[64],".json"))continue;
            bool valid=true;for(int i=0;i<64;i++)if(!((name[i]>='0'&&name[i]<='9')||(name[i]>='a'&&name[i]<='f')))valid=false;
            if(valid){Format(path,sizeof(path),"%s/%s",shopSessionDir,name);DeleteFile(path);}
        }
        delete files;
    }
    CreateTimer(3.0,ShopSession_Heartbeat,_,TIMER_REPEAT);
}

public void OnClientDisconnect(int client){ShopSession_Revoke(client);}
public void OnMapEnd(){for(int c=1;c<=MaxClients;c++)ShopSession_Revoke(c);}
