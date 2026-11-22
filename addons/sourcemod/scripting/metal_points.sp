#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

public Plugin myinfo = {name="Metal Points", author="Nomyname", description="Steam-confirmed metal deposit ledger", version="1.4.0"};
ArrayList g_Menus;
bool g_Ending;
Menu NewPointMenu(MenuHandler handler)
{
    Menu menu=new Menu(handler); g_Menus.Push(menu); return menu;
}
void EndPointMenu(Menu menu)
{
    if (g_Menus==null) return;
    int index=g_Menus.FindValue(menu); if(index<0) return;
    g_Menus.Erase(index); menu.Cancel(); delete menu;
}
public void OnPluginEnd()
{
    g_Ending=true;
    while(g_Menus!=null&&g_Menus.Length) EndPointMenu(view_as<Menu>(g_Menus.Get(g_Menus.Length-1)));
    delete g_Menus;
}
Database g_DB;
char g_Dir[PLATFORM_MAX_PATH];
bool g_Busy;
ConVar g_TradeURL;
int g_AmountUntil[MAXPLAYERS+1];
Handle g_PointHud;
bool g_HudQueryPending;
#include "metal_points_trade_url.inc"
#include "metal_points_withdraw.inc"
#include "metal_points_shop.inc"
#include "game_points.inc"

public void OnPluginStart()
{
    g_Menus=new ArrayList();
    char error[256];
    g_DB = SQLite_UseDatabase("metal_points", error, sizeof(error));
    if (g_DB == null) SetFailState("Point database: %s", error);
    if (!SQL_FastQuery(g_DB, "CREATE TABLE IF NOT EXISTS trade_urls(steamid TEXT PRIMARY KEY,url TEXT NOT NULL)"))
        SetFailState("Cannot initialize trade URL storage");
    if (!SQL_FastQuery(g_DB, "CREATE TABLE IF NOT EXISTS outgoing(code TEXT PRIMARY KEY,url TEXT NOT NULL,sent INTEGER NOT NULL DEFAULT 0)"))
        SetFailState("Cannot initialize outgoing queue");
    if (!SQL_FastQuery(g_DB, "CREATE TABLE IF NOT EXISTS accounts(steamid TEXT PRIMARY KEY, points INTEGER NOT NULL DEFAULT 0 CHECK(points>=0 AND points<=2000000000))")
        || !SQL_FastQuery(g_DB, "CREATE TABLE IF NOT EXISTS deposits(trade TEXT PRIMARY KEY, offer TEXT NOT NULL UNIQUE, steamid TEXT NOT NULL, points INTEGER NOT NULL CHECK(points BETWEEN 10 AND 90000), credited INTEGER NOT NULL DEFAULT 0)"))
        SetFailState("Cannot initialize point ledger");
    if (!SQL_FastQuery(g_DB, "CREATE TABLE IF NOT EXISTS withdrawals(code TEXT PRIMARY KEY,steamid TEXT NOT NULL,points INTEGER NOT NULL CHECK(points BETWEEN 10 AND 90000 AND points%10=0),status TEXT NOT NULL DEFAULT 'reserved',offer TEXT UNIQUE,trade TEXT)")
        || !SQL_FastQuery(g_DB, "CREATE UNIQUE INDEX IF NOT EXISTS one_withdrawal ON withdrawals(steamid) WHERE status IN ('reserved','claimed')"))
        SetFailState("Cannot initialize withdrawal ledger");
    BuildPath(Path_SM, g_Dir, sizeof(g_Dir), "data/metal_points");
    GamePointsInit();WalletStart();
    if (!DirExists(g_Dir)) CreateDirectory(g_Dir, 493);
    g_TradeURL = CreateConVar("sm_metal_points_trade_url", "", "Bot trade offer URL");
    AutoExecConfig(true, "metal_points");
    RegConsoleCmd("sm_points", CommandPoints);
    AddCommandListener(OnSay, "say");
    AddCommandListener(OnSay, "say_team");
    CreateTimer(5.0, PollReceipts, _, TIMER_REPEAT);
    g_PointHud = CreateHudSynchronizer();
    CreateTimer(1.0, UpdatePointHud, _, TIMER_REPEAT);
}

public Action UpdatePointHud(Handle timer)
{
    if (g_HudQueryPending) return Plugin_Continue;
    char query[4096] = "SELECT steamid,points FROM play_accounts WHERE steamid IN (";
    ArrayList clients = new ArrayList();
    for (int client=1; client<=MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client)) continue;
        char id[32], entry[40];
        if (!GetClientAuthId(client, AuthId_SteamID64, id, sizeof(id)) || !Digits(id,17,17)) continue;
        Format(entry,sizeof(entry),"%s'%s'",clients.Length ? "," : "",id);
        StrCat(query,sizeof(query),entry);
        clients.Push(GetClientSerial(client));
    }
    if (!clients.Length) { delete clients; return Plugin_Continue; }
    StrCat(query,sizeof(query),")");
    g_HudQueryPending = true;
    g_DB.Query(PointHudResult,query,clients);
    return Plugin_Continue;
}
public void PointHudResult(Database db, DBResultSet results, const char[] error, ArrayList clients)
{
    g_HudQueryPending = false;
    if (results == null) { LogError("Point HUD lookup: %s",error); delete clients; return; }
    StringMap balances = new StringMap();
    char id[32];
    while (results.FetchRow())
    {
        results.FetchString(0,id,sizeof(id));
        balances.SetValue(id,results.FetchInt(1));
    }
    SetHudTextParams(0.78,0.04,1.5,255,255,0,255,0,0.0,0.0,0.0);
    for (int i=0; i<clients.Length; i++)
    {
        int client = GetClientFromSerial(clients.Get(i));
        if (!client || !IsClientInGame(client) || !GetClientAuthId(client,AuthId_SteamID64,id,sizeof(id))) continue;
        int amount = 0;
        balances.GetValue(id,amount);
        ShowSyncHudText(client,g_PointHud,"게임 포인트 : %d",amount);
    }
    delete balances;
    delete clients;
}

public Action OnSay(int client, const char[] command, int argc)
{
    if (client < 1) return Plugin_Continue;
    char text[512]; GetCmdArgString(text, sizeof(text)); StripQuotes(text); TrimString(text);
    if (HandleTradeURLChat(client,text)) return Plugin_Handled;
    if (g_AmountUntil[client] > GetTime() && Digits(text, 1, 5))
    {
        g_AmountUntil[client] = 0;
        int amount = StringToInt(text);
        if (amount < 10 || amount > 90000 || amount % 10 != 0) PrintToChat(client, "[포인트] 10~90000 범위에서 10의 배수로 입력하세요.");
        else ConfirmWithdrawal(client, amount);
        return Plugin_Handled;
    }
    if (!StrEqual(text, "!포인트") && !StrEqual(text, "/포인트")) return Plugin_Continue;
    CommandPoints(client, 0);
    return Plugin_Handled;
}
public Action CommandPoints(int client, int args)
{
    if(g_Ending) return Plugin_Handled;
    if (client < 1 || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
    g_URLUntil[client]=0; g_AmountUntil[client]=0;
    FakeClientCommand(client,"sm_botpoints");
    return Plugin_Handled;
}
public int PointMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End) EndPointMenu(menu);
    else if (!g_Ending && action == MenuAction_Select)
    {
        if (item == 0)
        {
            char id[32], query[256];
            if (!GetClientAuthId(client, AuthId_SteamID64, id, sizeof(id))) return 0;
            Format(query, sizeof(query), "SELECT points FROM accounts WHERE steamid='%s'", id);
            g_DB.Query(ShowBalance, query, GetClientUserId(client));
        }
        else if (item == 1)
        {
            char url[256]; g_TradeURL.GetString(url, sizeof(url));
            PrintToChat(client, "[포인트] 폐기 10 / 재활용 30 / 정제 90 포인트");
            PrintToChat(client, "[포인트] 메시지 없이 봇에 금속만 보내면 자동 충전됩니다.");
            PrintToChat(client, "[포인트] 거래 보류 중에는 지급되지 않습니다. 완료 확인 후 자동 적립됩니다.");
            if (url[0])
            {
                // Match !st: dismiss the old panel and let the menu close before opening.
                ShowVGUIPanel(client, "info", INVALID_HANDLE, false);
                CreateTimer(0.15, ShowDepositPanel, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
                PrintToChat(client, "[포인트] %s", url);
            }
            else PrintToChat(client, "[포인트] 봇 연결 준비 중입니다. 아직 금속을 보내지 마세요.");
        }
        else if (item == 2) ShowWithdrawal(client);
        else if (item == 3)
        {
            g_AmountUntil[client]=0; g_URLUntil[client]=GetTime()+60;
            PrintToChat(client,"[포인트] 본인의 Steam 거래 URL을 채팅에 붙여넣으세요. 60초 이내 / 취소: 취소");
            PrintToChat(client,"[포인트] Steam 인벤토리 → 거래 제안 → 거래 제안을 보낼 수 있는 사람? 에서 복사하세요.");
        }
    }
    return 0;
}
public Action ShowDepositPanel(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (!client || !IsClientInGame(client)) return Plugin_Stop;
    char url[256]; g_TradeURL.GetString(url, sizeof(url));
    if (!url[0]) return Plugin_Stop;
    // VGUIMenu has a 255-byte limit; these fixed fields occupy 96 UTF-8 bytes.
    if (strlen(url) > 159)
    {
        PrintToChat(client, "[포인트] 거래 주소가 창 표시 한도를 넘습니다. 채팅 링크를 이용해 주세요.");
        LogError("Deposit MOTD URL exceeds 159-byte budget");
        return Plugin_Stop;
    }
    KeyValues panel = new KeyValues("data");
    panel.SetString("title", "포인트충전 - 어쩔티비 거래제안");
    panel.SetNum("type", MOTDPANEL_TYPE_URL);
    panel.SetString("msg", url);
    panel.SetNum("customsvr", 1);
    panel.SetNum("unload", 1);
    panel.SetNum("cmd", 0);
    ShowVGUIPanel(client, "info", panel, true);
    delete panel;
    return Plugin_Stop;
}
public void ShowBalance(Database db, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!client) return;
    if (results == null) { LogError("Balance lookup: %s", error); PrintToChat(client, "[포인트] 조회 실패. 잠시 후 다시 시도하세요."); return; }
    int amount = results.FetchRow() ? results.FetchInt(0) : 0;
    PrintToChat(client, "[포인트] 보유: %d 포인트 (RPG 화폐와 별도)", amount);
}
bool Digits(const char[] value, int min, int max)
{
    int n = strlen(value);
    if (n < min || n > max) return false;
    for (int i; i < n; i++) if (value[i] < '0' || value[i] > '9') return false;
    return true;
}
public Action PollReceipts(Handle timer)
{
    char heartbeat[PLATFORM_MAX_PATH];
    Format(heartbeat, sizeof(heartbeat), "%s/ready", g_Dir);
    File ready = OpenFile(heartbeat, "w");
    if (ready != null) { ready.WriteLine("%d", GetTime()); delete ready; }
    if (g_Busy) return Plugin_Continue;
    WalletSnapshot();GamePointsSnapshot();
    ExportOutgoing();
    DirectoryListing d = OpenDirectory(g_Dir);
    if (d == null) return Plugin_Continue;
    char name[128], path[PLATFORM_MAX_PATH]; FileType type;
    while (d.GetNext(name, sizeof(name), type))
    {
        if(type==FileType_File&&WalletFile(name))break;
        if (type == FileType_File && ProcessWithdrawalFile(name)) break;
        int n = strlen(name);
        if (type != FileType_File || n < 5 || !StrEqual(name[n-4], ".evt")) continue;
        name[n-4] = '\0';
        if (!Digits(name, 1, 20)) continue;
        Format(path, sizeof(path), "%s/%s.evt", g_Dir, name);
        File f = OpenFile(path, "r");
        if (f == null) continue;
        char line[128], field[4][32]; bool read = f.ReadLine(line, sizeof(line)); delete f;
        TrimString(line);
        if (!read || ExplodeString(line, " ", field, 4, 32) != 4
            || !StrEqual(field[0], name) || !Digits(field[0], 1, 20) || !Digits(field[1], 1, 20)
            || !Digits(field[2], 17, 17) || StrContains(field[2], "7656119") != 0 || !Digits(field[3], 2, 5)) continue;
        int points = StringToInt(field[3]);
        if (points < 10 || points > 90000 || points % 10 != 0) continue;
        Transaction txn = new Transaction(); char query[768];
        Format(query, sizeof(query), "INSERT OR IGNORE INTO deposits(trade,offer,steamid,points) VALUES('%s','%s','%s',%d)", field[0],field[1],field[2],points); txn.AddQuery(query);
        Format(query, sizeof(query), "INSERT OR IGNORE INTO accounts(steamid) VALUES('%s')", field[2]); txn.AddQuery(query);
        Format(query, sizeof(query), "UPDATE accounts SET points=points+COALESCE((SELECT points FROM deposits WHERE trade='%s' AND offer='%s' AND steamid='%s' AND points=%d AND credited=0),0) WHERE steamid='%s'",field[0],field[1],field[2],points,field[2]); txn.AddQuery(query);
        Format(query, sizeof(query), "UPDATE deposits SET credited=1 WHERE trade='%s' AND offer='%s' AND steamid='%s' AND points=%d",field[0],field[1],field[2],points); txn.AddQuery(query);
        Format(query, sizeof(query), "SELECT credited FROM deposits WHERE trade='%s' AND offer='%s' AND steamid='%s' AND points=%d",field[0],field[1],field[2],points); txn.AddQuery(query);
        DataPack pack = new DataPack(); pack.WriteString(name);
        g_Busy = true; g_DB.Execute(txn, DepositDone, DepositFailed, pack);
        break;
    }
    delete d;
    return Plugin_Continue;
}
public void DepositDone(Database db, DataPack pack, int count, DBResultSet[] results, any[] data)
{
    char name[32], src[PLATFORM_MAX_PATH], dst[PLATFORM_MAX_PATH]; pack.Reset(); pack.ReadString(name,sizeof(name)); delete pack;
    g_Busy = false;
    if (!results[4].FetchRow() || results[4].FetchInt(0) != 1) { LogError("Conflicting deposit receipt %s; manual review required", name); return; }
    WalletSnapshot();
    Format(src,sizeof(src),"%s/%s.evt",g_Dir,name); Format(dst,sizeof(dst),"%s/%s.done",g_Dir,name);
    if (!RenameFile(dst,src)) LogError("Receipt %s credited; archival retry required",name);
    else LogMessage("Metal receipt %s credited and archived",name);
}
public void DepositFailed(Database db, DataPack pack, int count, const char[] error, int failIndex, any[] data)
{
    delete pack; g_Busy = false; LogError("Deposit transaction rolled back (%d): %s",failIndex,error);
}
