public void OnClientDisconnect(int client) { g_AmountUntil[client]=0; g_URLUntil[client]=0; }

bool g_ExportPending;
void ExportOutgoing()
{
    if(g_Ending||g_ExportPending) return;
    g_ExportPending=true;
    g_DB.Query(OutgoingExported,"SELECT w.code,w.steamid,w.points,o.url FROM withdrawals w JOIN outgoing o ON o.code=w.code WHERE w.status='claimed' AND w.offer IS NULL");
}
public void OutgoingExported(Database db,DBResultSet r,const char[] error,any data)
{
    g_ExportPending=false;
    if(g_Ending||r==null) return;
    char dst[PLATFORM_MAX_PATH],tmp[PLATFORM_MAX_PATH];
    Format(dst,sizeof(dst),"%s/outgoing.queue",g_Dir); Format(tmp,sizeof(tmp),"%s.tmp",dst);
    File file=OpenFile(tmp,"w"); if(file==null) return;
    bool ok=file.WriteLine("%d",GetTime());
    while(r.FetchRow())
    {
        char code[40],id[32],url[256]; r.FetchString(0,code,sizeof(code)); r.FetchString(1,id,sizeof(id)); r.FetchString(3,url,sizeof(url));
        if(!file.WriteLine("%s %s %d %s",code,id,r.FetchInt(2),url)) ok=false;
    }
    delete file;
    if(ok) RenameFile(dst,tmp);
}

void ShowWithdrawal(int client)
{
    char id[32], query[512];
    if (!GetClientAuthId(client,AuthId_SteamID64,id,sizeof(id))) return;
    Format(query,sizeof(query),"SELECT code,points,status,offer,EXISTS(SELECT 1 FROM outgoing o WHERE o.code=w.code),COALESCE((SELECT sent FROM outgoing o WHERE o.code=w.code),0) FROM withdrawals w WHERE steamid='%s' AND status IN ('reserved','claimed')",id);
    g_DB.Query(WithdrawalInfo,query,GetClientUserId(client));
}
public void WithdrawalInfo(Database db, DBResultSet r, const char[] error, any userid)
{
    if(g_Ending) return;
    int client=GetClientOfUserId(userid); if (!client) return;
    if (r==null) {LogError("Withdrawal lookup: %s",error); return;}
    if (!r.FetchRow())
    {
        char url[256]; g_TradeURL.GetString(url,sizeof(url));
        if (!url[0]) {PrintToChat(client,"[포인트] 봇 연결 준비 중입니다. 반환 예약은 아직 할 수 없습니다."); return;}
        g_AmountUntil[client]=GetTime()+60;
        PrintToChat(client,"[포인트] 반환할 포인트를 채팅에 입력하세요. 10의 배수, 최대 90000. 60초 후 취소됩니다.");
        return;
    }
    char code[40], status[24], title[256]; r.FetchString(0,code,sizeof(code)); r.FetchString(2,status,sizeof(status));
    if(r.FetchInt(4))
    {
        char offer[32]; r.FetchString(3,offer,sizeof(offer));
        if(offer[0]&&r.FetchInt(5)) PrintToChat(client,"[포인트] 거래제안을 보냈습니다. Steam에서 확인해 주세요. https://steamcommunity.com/tradeoffer/%s/",offer);
        else if(r.FetchInt(1)>=5760) PrintToChat(client,"[포인트] 고액 출금은 주인의 Steam 채팅 승인 후 발송됩니다. 승인·재고 확인 대기 중입니다.");
        else PrintToChat(client,"[포인트] 거래제안 발송 대기 중입니다. 재고·거래 제한 확인 중에는 지연될 수 있습니다.");
        return;
    }
    int amount=r.FetchInt(1);
    Format(title,sizeof(title),"금속 반환: %d 포인트 예약됨\n폐기 %d개 상당 / 수수료 없음\n봇에서 금속을 요청하고 거래 메시지에\nWITHDRAW %s",amount,amount/10,code);
    Menu m=NewPointMenu(WithdrawalAction); m.SetTitle(title);
    m.AddItem("cancel","예약 취소",StrEqual(status,"reserved")?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
    m.Display(client,60);
    PrintToChat(client,"[포인트] 거래 메시지: WITHDRAW %s",code);
    char url[256]; g_TradeURL.GetString(url,sizeof(url)); PrintToChat(client,"[포인트] %s",url);
    if (StrEqual(status,"claimed")) PrintToChat(client,"[포인트] 거래 처리 중입니다. Steam에서 취소/실패 확인 후 자동 환불됩니다.");
}
public int WithdrawalAction(Menu menu,MenuAction action,int client,int item)
{
    if(action==MenuAction_End) EndPointMenu(menu);
    else if(!g_Ending && action==MenuAction_Select)
    {
        char id[32],q[512]; if(!GetClientAuthId(client,AuthId_SteamID64,id,sizeof(id))) return 0;
        Transaction t=new Transaction();
        Format(q,sizeof(q),"UPDATE accounts SET points=points+COALESCE((SELECT points FROM withdrawals WHERE steamid='%s' AND status='reserved'),0) WHERE steamid='%s'",id,id); t.AddQuery(q);
        Format(q,sizeof(q),"UPDATE withdrawals SET status='canceled' WHERE steamid='%s' AND status='reserved'",id); t.AddQuery(q);
        g_DB.Execute(t,CancelDone,UserTxnFailed,GetClientUserId(client));
    }
    return 0;
}
public void CancelDone(Database db,any userid,int count,DBResultSet[] r,any[] data)
{
    int c=GetClientOfUserId(userid); if(c) PrintToChat(c,"[포인트] 미처리 예약을 취소했습니다. 이미 거래 처리 중이면 완료/실패 확인을 기다려 주세요.");
}
void ConfirmWithdrawal(int client,int amount)
{
    PrintToChat(client,"[포인트] 아이템 충전·출금은 비활성화되었습니다.");
}
public int ConfirmAction(Menu menu,MenuAction action,int client,int item)
{
    if(action==MenuAction_End) EndPointMenu(menu);
    else if(false && !g_Ending && action==MenuAction_Select && item==0) // Item withdrawal disabled.
    {
        char v[16],id[32],code[40],q[768]; menu.GetItem(item,v,sizeof(v));
        int amount=StringToInt(v);
        if(!GetClientAuthId(client,AuthId_SteamID64,id,sizeof(id))) return 0;
        Format(code,sizeof(code),"%08x%08x%08x%08x",GetURandomInt(),GetURandomInt(),GetURandomInt(),GetURandomInt());
        Transaction t=new Transaction();
        Format(q,sizeof(q),"INSERT INTO withdrawals(code,steamid,points,status) SELECT '%s','%s',%d,'claimed' WHERE EXISTS(SELECT 1 FROM accounts WHERE steamid='%s' AND points>=%d) AND EXISTS(SELECT 1 FROM trade_urls WHERE steamid='%s') AND NOT EXISTS(SELECT 1 FROM withdrawals WHERE steamid='%s' AND status IN ('reserved','claimed'))",code,id,amount,id,amount,id,id); t.AddQuery(q);
        Format(q,sizeof(q),"UPDATE accounts SET points=points-%d WHERE steamid='%s' AND EXISTS(SELECT 1 FROM withdrawals WHERE code='%s')",amount,id,code); t.AddQuery(q);
        Format(q,sizeof(q),"SELECT code,points FROM withdrawals WHERE code='%s'",code); t.AddQuery(q);
        Format(q,sizeof(q),"INSERT INTO outgoing(code,url) SELECT '%s',url FROM trade_urls WHERE steamid='%s' AND EXISTS(SELECT 1 FROM withdrawals WHERE code='%s')",code,id,code); t.AddQuery(q);
        g_DB.Execute(t,ReserveDone,UserTxnFailed,GetClientUserId(client));
    }
    return 0;
}
public void ReserveDone(Database db,any userid,int count,DBResultSet[] r,any[] data)
{
    if(g_Ending) return;
    int c=GetClientOfUserId(userid); if(!c) return;
    if(!r[2].FetchRow()) {PrintToChat(c,"[포인트] 거래 URL 미등록, 잔액 부족 또는 진행 중인 반환 요청이 있습니다."); return;}
    if(r[2].FetchInt(1)>=5760) PrintToChat(c,"[포인트] 64정 이상 출금: 주인에게 Steam 채팅 승인 요청을 보냅니다. 거절되면 포인트가 환불됩니다.");
    else PrintToChat(c,"[포인트] 거래제안을 보내는 중입니다. 포인트는 완료 확인까지 예약됩니다.");
    ExportOutgoing();
}
public void UserTxnFailed(Database db,any userid,int count,const char[] error,int failed,any[] data)
{
    LogError("Withdrawal transaction rolled back: %s",error);
    int c=GetClientOfUserId(userid); if(c) PrintToChat(c,"[포인트] 처리 실패. 잔액은 변경되지 않았습니다.");
}
bool HexCode(const char[] code)
{
    if(strlen(code)!=32) return false;
    for(int i;i<32;i++) if(!((code[i]>='0'&&code[i]<='9')||(code[i]>='a'&&code[i]<='f'))) return false;
    return true;
}
bool ProcessWithdrawalFile(const char[] name)
{
    if(ProcessOwnerRejection(name)) return true;
    int n=strlen(name); bool settle=n>7&&StrEqual(name[n-7],".settle");
    bool claim=n>6&&StrEqual(name[n-6],".claim");
    bool bind=n>5&&StrEqual(name[n-5],".bind");
    bool sent=n>5&&StrEqual(name[n-5],".sent");
    if(!settle&&!claim&&!bind&&!sent) return false;
    if(n > 27) return false;
    char offer[32]; strcopy(offer,sizeof(offer),name); offer[n-(settle?7:((bind||sent)?5:6))]='\0';
    if(!Digits(offer,1,20)) return false;
    char path[PLATFORM_MAX_PATH],line[192],f[6][40];
    Format(path,sizeof(path),"%s/%s",g_Dir,name);
    File file=OpenFile(path,"r"); if(file==null) return false;
    bool ok=file.ReadLine(line,sizeof(line)); delete file; TrimString(line);
    int fields=ExplodeString(line," ",f,6,40);
    if(!ok||fields!=(settle?6:4)||!StrEqual(f[0],offer)||!HexCode(f[1])||!Digits(f[2],17,17)||StrContains(f[2],"7656119")!=0||!Digits(f[3],2,5)) return false;
    int points=StringToInt(f[3]); if(points<10||points>90000||points%10!=0) return false;
    if(settle&&((!StrEqual(f[4],"completed")&&!StrEqual(f[4],"failed"))||!Digits(f[5],1,20))) return false;
    Transaction t=new Transaction(); char q[1024],where[512];
    Format(where,sizeof(where),"code='%s' AND steamid='%s' AND points=%d",f[1],f[2],points);
    if(sent)
    {
        Format(q,sizeof(q),"UPDATE outgoing SET sent=1 WHERE code='%s' AND EXISTS(SELECT 1 FROM withdrawals WHERE %s AND status='claimed' AND offer='%s')",f[1],where,offer); t.AddQuery(q);
    }
    else if(bind)
    {
        Format(q,sizeof(q),"UPDATE withdrawals SET offer='%s' WHERE %s AND status='claimed' AND offer IS NULL AND EXISTS(SELECT 1 FROM outgoing WHERE code='%s')",offer,where,f[1]); t.AddQuery(q);
    }
    else if(claim)
    {
        Format(q,sizeof(q),"UPDATE withdrawals SET offer='%s',status='claimed' WHERE %s AND status='reserved'",offer,where); t.AddQuery(q);
    }
    else if(StrEqual(f[4],"failed"))
    {
        Format(q,sizeof(q),"UPDATE accounts SET points=points+COALESCE((SELECT points FROM withdrawals WHERE %s AND offer='%s' AND status='claimed'),0) WHERE steamid='%s'",where,offer,f[2]); t.AddQuery(q);
        Format(q,sizeof(q),"UPDATE withdrawals SET status='refunded' WHERE %s AND offer='%s' AND status='claimed'",where,offer); t.AddQuery(q);
    }
    else
    {
        Format(q,sizeof(q),"UPDATE withdrawals SET status='completed',trade='%s' WHERE %s AND offer='%s' AND status='claimed'",f[5],where,offer); t.AddQuery(q);
    }
    Format(q,sizeof(q),"SELECT status,offer FROM withdrawals WHERE %s",where); t.AddQuery(q);
    DataPack p=new DataPack(); p.WriteString(name); p.WriteString(line); p.WriteString(offer); p.WriteCell(claim||bind||sent); p.WriteString(f[4]);
    g_Busy=true; g_DB.Execute(t,WithdrawalFileDone,DepositFailed,p); return true;
}

bool ProcessOwnerRejection(const char[] name)
{
    if(strlen(name)!=39||!StrEqual(name[32],".reject")) return false;
    char code[40];strcopy(code,sizeof(code),name);code[32]='\0';if(!HexCode(code)) return false;
    char path[PLATFORM_MAX_PATH],line[128],f[3][40];Format(path,sizeof(path),"%s/%s",g_Dir,name);
    File file=OpenFile(path,"r");if(file==null) return false;
    bool ok=file.ReadLine(line,sizeof(line));delete file;TrimString(line);
    if(!ok||ExplodeString(line," ",f,3,40)!=3||!StrEqual(f[0],code)||!Digits(f[1],17,17)||StrContains(f[1],"7656119")!=0||!Digits(f[2],4,5)) return false;
    int points=StringToInt(f[2]);if(points<5760||points>90000||points%10) return false;
    char where[512],q[1024];
    Format(where,sizeof(where),"code='%s' AND steamid='%s' AND points=%d AND status='claimed' AND offer IS NULL AND EXISTS(SELECT 1 FROM outgoing WHERE code='%s')",code,f[1],points,code);
    Transaction t=new Transaction();
    Format(q,sizeof(q),"UPDATE accounts SET points=points+COALESCE((SELECT points FROM withdrawals WHERE %s),0) WHERE steamid='%s'",where,f[1]);t.AddQuery(q);
    Format(q,sizeof(q),"UPDATE withdrawals SET status='refunded' WHERE %s",where);t.AddQuery(q);
    Format(q,sizeof(q),"SELECT status FROM withdrawals WHERE code='%s' AND steamid='%s' AND points=%d AND offer IS NULL",code,f[1],points);t.AddQuery(q);
    DataPack pack=new DataPack();pack.WriteString(name);pack.WriteString(line);pack.WriteString(f[1]);
    g_Busy=true;g_DB.Execute(t,OwnerRejectionDone,DepositFailed,pack);return true;
}
public void OwnerRejectionDone(Database db,DataPack pack,int count,DBResultSet[] r,any[] data)
{
    char name[64],line[128],id[32],status[24],result[16]="denied";
    pack.Reset();pack.ReadString(name,sizeof(name));pack.ReadString(line,sizeof(line));pack.ReadString(id,sizeof(id));delete pack;
    if(r[2].FetchRow()) {r[2].FetchString(0,status,sizeof(status));if(StrEqual(status,"refunded")) strcopy(result,sizeof(result),"refunded");}
    char src[PLATFORM_MAX_PATH],tmp[PLATFORM_MAX_PATH],dst[PLATFORM_MAX_PATH];
    Format(src,sizeof(src),"%s/%s",g_Dir,name);Format(tmp,sizeof(tmp),"%s.reply",src);Format(dst,sizeof(dst),"%s.done",src);
    File file=OpenFile(tmp,"w");
    if(file!=null) {
        bool ok=file.WriteLine("%s",line)&&file.WriteLine("%s",result);delete file;
        if(ok&&RenameFile(dst,tmp)) {
            DeleteFile(src);
            if(StrEqual(result,"refunded")) for(int c=1;c<=MaxClients;c++) {
                char who[32];if(IsClientInGame(c)&&!IsFakeClient(c)&&GetClientAuthId(c,AuthId_SteamID64,who,sizeof(who))&&StrEqual(who,id)) PrintToChat(c,"[포인트] 주인이 출금을 거절하여 예약 포인트를 환불했습니다.");
            }
        }
    }
    g_Busy=false;
}
public void WithdrawalFileDone(Database db,DataPack p,int count,DBResultSet[] r,any[] data)
{
    char name[64],line[192],offer[32],expected[24]; p.Reset(); p.ReadString(name,sizeof(name)); p.ReadString(line,sizeof(line)); p.ReadString(offer,sizeof(offer)); bool claim=p.ReadCell()!=0; p.ReadString(expected,sizeof(expected)); delete p;
    char result[24]="denied",status[24],bound[32];
    if(r[count-1].FetchRow())
    {
        r[count-1].FetchString(0,status,sizeof(status)); r[count-1].FetchString(1,bound,sizeof(bound));
        if(StrEqual(bound,offer))
        {
            if(claim&&StrEqual(status,"claimed")) strcopy(result,sizeof(result),"authorized");
            else if(!claim&&((StrEqual(expected,"completed")&&StrEqual(status,"completed"))||(StrEqual(expected,"failed")&&StrEqual(status,"refunded")))) strcopy(result,sizeof(result),"settled");
        }
    }
    char src[PLATFORM_MAX_PATH],dst[PLATFORM_MAX_PATH],tmp[PLATFORM_MAX_PATH];
    Format(src,sizeof(src),"%s/%s",g_Dir,name); Format(dst,sizeof(dst),"%s.done",src); Format(tmp,sizeof(tmp),"%s.reply",src);
    File file=OpenFile(tmp,"w");
    if(file!=null)
    {
        bool ok=file.WriteLine("%s",line)&&file.WriteLine("%s",result); delete file;
        if(ok&&RenameFile(dst,tmp))
        {
            DeleteFile(src);
            char fields[6][40]; ExplodeString(line," ",fields,6,40);
            for(int c=1;c<=MaxClients;c++)
            {
                char id[32];
                if(!IsClientInGame(c)||IsFakeClient(c)||!GetClientAuthId(c,AuthId_SteamID64,id,sizeof(id))||!StrEqual(id,fields[2])) continue;
                if(StrEqual(result,"authorized")&&StrContains(name,".sent")!=-1)
                    PrintToChat(c,"[포인트] 거래제안을 보냈습니다. Steam에서 확인해 주세요. https://steamcommunity.com/tradeoffer/%s/",offer);
                else if(StrEqual(result,"settled"))
                    PrintToChat(c,StrEqual(expected,"completed")?"[포인트] 금속 반환이 완료되었습니다.":"[포인트] 거래 취소·실패가 확인되어 예약 포인트를 환불했습니다.");
            }
        }
        else LogError("Withdrawal receipt archive failed: %s",name);
    }
    g_Busy=false;
}
