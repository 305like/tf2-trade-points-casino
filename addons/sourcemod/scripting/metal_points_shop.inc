#define POINT_OWNER "76561198038759714"
bool WalletURL(const char[] url,const char[] id)
{
    char base[]="76561197960265728",account[18];int borrow;
    for(int i=16;i>=0;i--){int digit=id[i]-base[i]-borrow;borrow=digit<0?1:0;if(borrow)digit+=10;account[i]='0'+digit;}
    account[17]='\0';if(borrow)return false;
    int start;while(start<16&&account[start]=='0')start++;
    return ValidPlayerTradeURL(url,account[start]);
}

void WalletStart()
{
    if(!SQL_FastQuery(g_DB,"CREATE TABLE IF NOT EXISTS wallet_actions(code TEXT PRIMARY KEY,actor TEXT NOT NULL,target TEXT NOT NULL,kind TEXT NOT NULL,amount INTEGER NOT NULL,created INTEGER NOT NULL,balance INTEGER NOT NULL)"))SetFailState("Wallet audit initialization failed");
}
void WalletSnapshot()
{
    char day[16],backup[PLATFORM_MAX_PATH],backupStage[PLATFORM_MAX_PATH],backupQuery[512];FormatTime(day,sizeof(day),"%Y-%m-%d",GetTime());
    Format(backup,sizeof(backup),"%s/ledger-%s.sq3",g_Dir,day);
    if(!FileExists(backup)){
        Format(backupStage,sizeof(backupStage),"%s.new",backup);if(FileExists(backupStage)&&!DeleteFile(backupStage))return;
        Format(backupQuery,sizeof(backupQuery),"VACUUM INTO '/home/container/tf/addons/sourcemod/data/metal_points/ledger-%s.sq3.new'",day);
        if(!SQL_FastQuery(g_DB,backupQuery)||!SetFilePermissions(backupStage,384)||!RenameFile(backup,backupStage)){LogError("Daily point ledger backup failed");return;}
    }
    char path[PLATFORM_MAX_PATH],temp[PLATFORM_MAX_PATH];
    Format(path,sizeof(path),"%s/wallet.snapshot",g_Dir);Format(temp,sizeof(temp),"%s.new",path);
    DBResultSet totals=SQL_Query(g_DB,"SELECT COALESCE((SELECT SUM(points) FROM accounts),0),COALESCE((SELECT SUM(points) FROM withdrawals WHERE status IN ('reserved','claimed')),0)");
    if(totals==null)return;
    if(!totals.FetchRow()){delete totals;return;}
    char points[32],pending[32];totals.FetchString(0,points,sizeof(points));totals.FetchString(1,pending,sizeof(pending));delete totals;
    DBResultSet rows=SQL_Query(g_DB,"SELECT steamid,points FROM accounts");if(rows==null)return;
    File f=OpenFile(temp,"w");if(f==null){delete rows;return;}
    bool ok=f.WriteLine("%d",GetTime())&&f.WriteLine("%s %s",points,pending);
    while(rows.FetchRow()){char id[32];rows.FetchString(0,id,sizeof(id));ok=f.WriteLine("%s %d",id,rows.FetchInt(1))&&ok;}
    delete rows;delete f;if(ok)ok=SetFilePermissions(temp,420)&&RenameFile(path,temp);
    if(!ok)LogError("Wallet snapshot write failed");
}
bool WalletFile(const char[] name)
{
    if(strlen(name)!=39||!StrEqual(name[32],".wallet"))return false;
    for(int i;i<32;i++)if(!((name[i]>='0'&&name[i]<='9')||(name[i]>='a'&&name[i]<='f')))return false;
    char path[PLATFORM_MAX_PATH],line[512],v[7][192];Format(path,sizeof(path),"%s/%s",g_Dir,name);
    File f=OpenFile(path,"r");if(f==null)return true;bool read=f.ReadLine(line,sizeof(line));delete f;TrimString(line);
    char code[40];strcopy(code,sizeof(code),name);code[32]='\0';
    if(!read||ExplodeString(line," ",v,7,192)!=7||!StrEqual(code,v[0])||!Digits(v[1],17,17)||!Digits(v[2],17,17)
        ||StrContains(v[1],"7656119")!=0||StrContains(v[2],"7656119")!=0)return true;
    bool adjust=StrEqual(v[3],"play_adjust"),withdraw=StrEqual(v[3],"withdraw");
    if(!adjust)return true; // Item-linked adjustments and new withdrawals are disabled.
    if(adjust&&!StrEqual(v[1],POINT_OWNER))return true;
    if(withdraw&&!StrEqual(v[1],v[2]))return true;
    int offset=v[4][0]=='-'?1:0;if(!Digits(v[4][offset],1,5))return true;
    int amount=StringToInt(v[4]);if(!amount||amount>90000||amount< -90000)return true;
    if(withdraw&&(amount<10||amount%10!=0||!WalletURL(v[6],v[2])))return true;
    if(!Digits(v[5],1,10))return true;
    char query[2048],result[32]="failed";bool ok;
    SQL_LockDatabase(g_DB);
    ok=SQL_FastQuery(g_DB,"BEGIN IMMEDIATE");
    if(ok){
        Format(query,sizeof(query),"SELECT actor,target,kind,amount FROM wallet_actions WHERE code='%s'",code);
        DBResultSet previous=SQL_Query(g_DB,query);
        if(previous!=null&&previous.FetchRow()){
            char actor[32],target[32],kind[24];previous.FetchString(0,actor,sizeof(actor));previous.FetchString(1,target,sizeof(target));previous.FetchString(2,kind,sizeof(kind));
            if(StrEqual(actor,v[1])&&StrEqual(target,v[2])&&StrEqual(kind,v[3])&&previous.FetchInt(3)==amount)strcopy(result,sizeof(result),"completed");
            SQL_FastQuery(g_DB,"ROLLBACK");
        }else if(previous!=null){
            Format(query,sizeof(query),"INSERT OR IGNORE INTO play_accounts(steamid) VALUES('%s')",v[2]);ok=SQL_FastQuery(g_DB,query);
            if(adjust){
                Format(query,sizeof(query),"INSERT INTO wallet_actions SELECT '%s','%s','%s','play_adjust',%d,%s,points+%d FROM play_accounts WHERE steamid='%s' AND points+%d BETWEEN 0 AND 2000000000",code,v[1],v[2],amount,v[5],amount,v[2],amount);ok=ok&&SQL_FastQuery(g_DB,query);
                Format(query,sizeof(query),"UPDATE play_accounts SET points=points+%d WHERE steamid='%s' AND EXISTS(SELECT 1 FROM wallet_actions WHERE code='%s')",amount,v[2],code);ok=ok&&SQL_FastQuery(g_DB,query);
            }else{
                Format(query,sizeof(query),"INSERT INTO withdrawals(code,steamid,points,status) SELECT '%s','%s',%d,'claimed' WHERE EXISTS(SELECT 1 FROM accounts WHERE steamid='%s' AND points>=%d) AND NOT EXISTS(SELECT 1 FROM withdrawals WHERE steamid='%s' AND status IN ('reserved','claimed'))",code,v[2],amount,v[2],amount,v[2]);ok=ok&&SQL_FastQuery(g_DB,query);
                Format(query,sizeof(query),"UPDATE accounts SET points=points-%d WHERE steamid='%s' AND EXISTS(SELECT 1 FROM withdrawals WHERE code='%s')",amount,v[2],code);ok=ok&&SQL_FastQuery(g_DB,query);
                Format(query,sizeof(query),"INSERT INTO outgoing(code,url) SELECT '%s','%s' WHERE EXISTS(SELECT 1 FROM withdrawals WHERE code='%s')",code,v[6],code);ok=ok&&SQL_FastQuery(g_DB,query);
                Format(query,sizeof(query),"INSERT INTO wallet_actions SELECT '%s','%s','%s','withdraw',%d,%s,points FROM accounts WHERE steamid='%s' AND EXISTS(SELECT 1 FROM withdrawals WHERE code='%s')",code,v[1],v[2],amount,v[5],v[2],code);ok=ok&&SQL_FastQuery(g_DB,query);
            }
            Format(query,sizeof(query),"SELECT code FROM wallet_actions WHERE code='%s'",code);DBResultSet applied=SQL_Query(g_DB,query);
            ok=ok&&applied!=null&&applied.FetchRow();delete applied;
            if(ok&&SQL_FastQuery(g_DB,"COMMIT"))strcopy(result,sizeof(result),"completed");else SQL_FastQuery(g_DB,"ROLLBACK");
        }else SQL_FastQuery(g_DB,"ROLLBACK");
        delete previous;
    }
    SQL_UnlockDatabase(g_DB);
    WalletSnapshot();GamePointsSnapshot();ExportOutgoing();
    char done[PLATFORM_MAX_PATH],temp[PLATFORM_MAX_PATH];Format(done,sizeof(done),"%s.done",path);Format(temp,sizeof(temp),"%s.new",done);
    f=OpenFile(temp,"w");if(f!=null){ok=f.WriteLine("%s",line)&&f.WriteLine("%s",result);delete f;if(ok&&SetFilePermissions(temp,420)&&RenameFile(done,temp))DeleteFile(path);}
    return true;
}
