// This ledger has no item ingress, egress, transfer or conversion path.
public APLRes AskPluginLoad2(Handle myself,bool late,char[] error,int maxlen)
{
    CreateNative("GamePoints_Don",GamePointsNative);return APLRes_Success;
}
void GamePointsInit()
{
    if(!SQL_FastQuery(g_DB,"CREATE TABLE IF NOT EXISTS play_accounts(steamid TEXT PRIMARY KEY,points INTEGER NOT NULL DEFAULT 0 CHECK(points BETWEEN 0 AND 2000000000))")
        ||!SQL_FastQuery(g_DB,"CREATE TABLE IF NOT EXISTS play_rounds(id INTEGER PRIMARY KEY AUTOINCREMENT,steamid TEXT NOT NULL,bet INTEGER NOT NULL,amount INTEGER NOT NULL,closed INTEGER NOT NULL DEFAULT 0)")
        ||!SQL_FastQuery(g_DB,"CREATE UNIQUE INDEX IF NOT EXISTS one_play_round ON play_rounds(steamid) WHERE closed=0"))SetFailState("Game point ledger initialization failed");
}
// op 0: recover outstanding rounds after casino reload; 1: stake; 2: result; 3: collect.
public any GamePointsNative(Handle plugin,int params)
{
    int client=GetNativeCell(1),op=GetNativeCell(2),value=GetNativeCell(3),round=GetNativeCell(4),result=-1;
    char id[32],q[1024];
    if(op!=0&&(client<1||client>MaxClients||!GetClientAuthId(client,AuthId_SteamID64,id,sizeof(id),true)||!Digits(id,17,17)))return -1;
    if(op<0||op>4||op==1&&(value!=1&&value!=3&&value!=5)||op==2&&(value!=0&&value!=1))return -1;
    SQL_LockDatabase(g_DB);bool ok=SQL_FastQuery(g_DB,"BEGIN IMMEDIATE");
    if(ok){
        if(op==0||op==4){
            char where[96];if(op==4)Format(where,sizeof(where)," AND steamid='%s'",id);
            Format(q,sizeof(q),"UPDATE play_accounts SET points=points+COALESCE((SELECT amount FROM play_rounds WHERE steamid=play_accounts.steamid AND closed=0),0) WHERE 1=1%s",where);ok=SQL_FastQuery(g_DB,q);
            Format(q,sizeof(q),"UPDATE play_rounds SET closed=1 WHERE closed=0%s",where);ok=ok&&SQL_FastQuery(g_DB,q);result=0;
        }else if(op==1){
            Format(q,sizeof(q),"INSERT INTO play_rounds(steamid,bet,amount) SELECT '%s',%d,%d WHERE EXISTS(SELECT 1 FROM play_accounts WHERE steamid='%s' AND points>=%d) AND NOT EXISTS(SELECT 1 FROM play_rounds WHERE steamid='%s' AND closed=0)",id,value,value,id,value,id);ok=SQL_FastQuery(g_DB,q);
            Format(q,sizeof(q),"SELECT id FROM play_rounds WHERE steamid='%s' AND closed=0",id);DBResultSet rows=SQL_Query(g_DB,q);
            DBResultSet changed=SQL_Query(g_DB,"SELECT changes()");ok=ok&&changed!=null&&changed.FetchRow()&&changed.FetchInt(0)==1;delete changed;
            if(ok&&rows!=null&&rows.FetchRow())result=rows.FetchInt(0);else ok=false;delete rows;
            Format(q,sizeof(q),"UPDATE play_accounts SET points=points-%d WHERE steamid='%s'",value,id);if(ok)ok=SQL_FastQuery(g_DB,q);
        }else{
            Format(q,sizeof(q),"SELECT amount FROM play_rounds WHERE id=%d AND steamid='%s' AND closed=0",round,id);DBResultSet rows=SQL_Query(g_DB,q);
            ok=rows!=null&&rows.FetchRow();int amount=ok?rows.FetchInt(0):0;delete rows;
            if(op==2){
                if(value&&amount>500000000)ok=false;
                result=value?amount*2:0;
                Format(q,sizeof(q),"UPDATE play_rounds SET amount=%d,closed=%d WHERE id=%d AND closed=0",result,result==0?1:0,round);if(ok)ok=SQL_FastQuery(g_DB,q);
            }else{
                Format(q,sizeof(q),"UPDATE play_accounts SET points=points+%d WHERE steamid='%s'",amount,id);if(ok)ok=SQL_FastQuery(g_DB,q);
                Format(q,sizeof(q),"UPDATE play_rounds SET closed=1 WHERE id=%d",round);if(ok)ok=SQL_FastQuery(g_DB,q);result=amount;
            }
        }
        if(!ok||!SQL_FastQuery(g_DB,"COMMIT")){SQL_FastQuery(g_DB,"ROLLBACK");result=-1;}
    }
    SQL_UnlockDatabase(g_DB);return result;
}
void GamePointsSnapshot()
{
    char path[PLATFORM_MAX_PATH],temp[PLATFORM_MAX_PATH];Format(path,sizeof(path),"%s/play.snapshot",g_Dir);Format(temp,sizeof(temp),"%s.new",path);
    DBResultSet rows=SQL_Query(g_DB,"SELECT steamid,points FROM play_accounts");if(rows==null)return;
    File f=OpenFile(temp,"w");if(f==null){delete rows;return;}
    bool ok=f.WriteLine("%d",GetTime())&&f.WriteLine("0 0");
    while(rows.FetchRow()){char id[32];rows.FetchString(0,id,sizeof(id));ok=f.WriteLine("%s %d",id,rows.FetchInt(1))&&ok;}
    delete rows;delete f;if(ok)ok=SetFilePermissions(temp,420)&&RenameFile(path,temp);
    if(!ok)LogError("Game point snapshot failed");
}
