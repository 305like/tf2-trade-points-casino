int g_URLUntil[MAXPLAYERS+1];

bool ValidPlayerTradeURL(const char[] url,const char[] account)
{
    char prefix[96];
    Format(prefix,sizeof(prefix),"https://steamcommunity.com/tradeoffer/new/?partner=%s&token=",account);
    int start=strlen(prefix);
    if (StrContains(url,prefix)!=0 || strlen(url)!=start+8) return false;
    for (int i=start;url[i];i++)
        if (!((url[i]>='a'&&url[i]<='z')||(url[i]>='A'&&url[i]<='Z')
            ||(url[i]>='0'&&url[i]<='9')||url[i]=='_'||url[i]=='-')) return false;
    return true;
}

bool HandleTradeURLChat(int client,const char[] text)
{
    // Suppress late pastes too; do not echo trade tokens to public chat.
    bool looksLikeURL=StrContains(text,"steamcommunity.com/tradeoffer",false)!=-1;
    if (g_URLUntil[client]<=GetTime())
    {
        if (looksLikeURL) PrintToChat(client,"[포인트] 먼저 !포인트 → 거래 URL 설정을 선택하세요. 주소는 저장되지 않았습니다.");
        return looksLikeURL;
    }
    if (StrEqual(text,"취소")||StrEqual(text,"cancel",false))
    {
        g_URLUntil[client]=0; PrintToChat(client,"[포인트] 거래 URL 입력을 취소했습니다."); return true;
    }
    if (StrEqual(text,"!포인트")||StrEqual(text,"/포인트"))
    {
        g_URLUntil[client]=0; CommandPoints(client,0); return true;
    }
    char account[16],id[32];
    int accountID=GetSteamAccountID(client);
    if (!accountID||!GetClientAuthId(client,AuthId_SteamID64,id,sizeof(id))||!Digits(id,17,17)) return true;
    Format(account,sizeof(account),"%u",accountID);
    if (!ValidPlayerTradeURL(text,account))
    {
        PrintToChat(client,"[포인트] 본인 계정의 HTTPS 거래 URL을 그대로 입력하세요. 잘못된 형식 또는 다른 계정의 주소입니다.");
        return true;
    }
    // Validated alphabet excludes SQL quotes and extra parameters.
    char query[512];
    Format(query,sizeof(query),"INSERT OR REPLACE INTO trade_urls(steamid,url) VALUES('%s','%s')",id,text);
    g_URLUntil[client]=0;
    g_DB.Query(TradeURLSaved,query,GetClientSerial(client));
    return true;
}

public void TradeURLSaved(Database db,DBResultSet result,const char[] error,any serial)
{
    int client=GetClientFromSerial(serial);
    if (result==null)
    {
        // Error text can contain the submitted URL.
        LogError("Trade URL save failed");
        if (client) PrintToChat(client,"[포인트] 저장 실패. 거래 URL 설정에서 다시 시도하세요.");
        return;
    }
    if (client) PrintToChat(client,"[포인트] 본인의 거래 URL을 저장했습니다. 변경할 때도 같은 메뉴에서 입력하세요.");
}
