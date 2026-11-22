#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#define TABLES 8
#define SEATS 6
#define COUNT 48
#define BASE_HEIGHT 0.0
#define VERSION "0.3.0"
#define MAX_CHIPS 1000000
#include "casino_hint.inc"
#include "casino_cards_rules.inc"
public Plugin myinfo={name="Casino Cards Test",author="Codex",description="Seated blackjack and fixed-limit Holdem; virtual chips only",version=VERSION};
enum struct Machine {
    int chair;
    int user;
    bool busy;
    float chairOrigin[3];
    float origin[3];
    float yaw;
}
Machine machines[COUNT];
enum struct Table {
    int body;
    int kind;
    float origin[3];
    float yaw;
    int phase;
    int dealer;
    int actor;
    int deck[52];
    int cursor;
    int board[5];
    int shown;
    int users[6];
    int hole[30];
    int discard[30];
    int discarded;
    int drawMask[6];
    int paid[6];
    int street[6];
    bool folded[6];
    bool pending[6];
    bool acted[6];
    int current;
    int raises;
    int revision;
    float due;
}
Table tables[TABLES];
enum struct BJ {
    bool active;
    int deck[52];
    int cursor;
    int hand[12];
    int dealer[12];
    int count;
    int dc;
    int wager;
    float due;
}
BJ blackjack[MAXPLAYERS+1];
int chips[MAXPLAYERS+1],bet[MAXPLAYERS+1],previous[MAXPLAYERS+1],revision[MAXPLAYERS+1],setupKind[MAXPLAYERS+1];
bool typing[MAXPLAYERS+1],ready,ending;
float nextUse[MAXPLAYERS+1],nextFrame;
ArrayList ownedMenus;
char models[][]={"models/tower_cards_v1/blackjack.mdl","models/tower_cards_v1/poker.mdl"};
char sounds[][]={"tower_cards_v1/CardFlip.wav","tower_cards_v1/CardShuffle.wav","tower_cards_v1/PokerRaise.wav","tower_cards_v1/PokerWin.wav","tower_cards_v1/PokerFold.wav","tower_cards_v1/PokerYourTurn.wav","tower_cards_v1/CardCheck.wav","tower_cards_v1/PokerReveal.wav","tower_cards_v1/PokerChipSmall01.wav","tower_cards_v1/BlackjackMajorWin.wav","tower_cards_v1/CardFold.wav"};
// Same tested seat/camera/weapon restoration implementation as the existing casino.
#define CARD_SEATS_IGNORE_MOUNT_CLEARANCE
#include "double_nothing_seats.inc"
#include "casino_cards_visuals.inc"

bool Player(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&IsPlayerAlive(c);}
bool Admin(int c){return c>0&&IsClientInGame(c)&&CheckCommandAccess(c,"sm_cardtable",ADMFLAG_GENERIC);}
int Entity(int ref){int e=EntRefToEntIndex(ref);return e>MaxClients&&IsValidEntity(e)?e:-1;}
int Prop(const char[] model,bool solid=false){
    int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return INVALID_ENT_REFERENCE;
    DispatchKeyValue(e,"model",model);DispatchKeyValue(e,"solid",solid?"6":"0");
    if(!DispatchSpawn(e)){RemoveEntity(e);return INVALID_ENT_REFERENCE;}
    SetEntProp(e,Prop_Data,"m_takedamage",0);return EntIndexToEntRef(e);
}
void Animate(int ref,const char[] sequence){int e=Entity(ref);if(e!=-1){SetVariantString(sequence);AcceptEntityInput(e,"SetAnimation");}}
public bool TraceWorld(int e,int mask,any data){return e==0;}
void WorldPoint(int s,float x,float y,float z,float p[3]){p=machines[s].origin;p[0]+=x;p[1]+=y;p[2]+=z;}
void UpdateDisplay(int s){int c=GetClientOfUserId(machines[s].user);if(c>0){revision[c]++;CasinoHint(c,"E/메딕 호출: 카드 메뉴 · Ctrl: 하차/포기 · 휠: 1/3인칭\n가상 칩 시험용 · 실제 포인트 사용 안 함");ShowGame(c);}}
void Release(int s){
    int c=GetClientOfUserId(machines[s].user);machines[s].user=0;
    if(c>0){typing[c]=false;revision[c]++;blackjack[c].active=false;}
    int t=s/6,i=s%6;
    if(c>0)viewBJHold[c]=0.0;
    if(tables[t].kind==0)ViewCollect(t,i*24,(i+1)*24);
    if(tables[t].phase&&tables[t].users[i]){
        tables[t].folded[i]=true;tables[t].pending[i]=false;
        if(!ending)Advance(t,(tables[t].actor+5)%6);
    }
}
public void OnPluginStart(){
    CardRulesTest();ownedMenus=new ArrayList();SeatsInit();
    RegAdminCmd("sm_cardtable",Setup,ADMFLAG_GENERIC);
    RegAdminCmd("sm_cardtable_status",Status,ADMFLAG_GENERIC);
    RegAdminCmd("sm_cardtable_selftest",SelfTest,ADMFLAG_ROOT);
    RegAdminCmd("sm_cardtable_visualtest",ViewSelfTest,ADMFLAG_ROOT);
    RegConsoleCmd("sm_cards",OpenGame);
    AddCommandListener(Chat,"say");AddCommandListener(Chat,"say_team");
    AddCommandListener(CardMedicCall,"voicemenu");
    for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c))OnClientPutInServer(c);
}
public void OnMapStart(){
    ready=false;CasinoHintReset();
    for(int t=0;t<TABLES;t++){Table blank;tables[t]=blank;tables[t].dealer=5;}
    for(int s=0;s<COUNT;s++){Machine blank;machines[s]=blank;}
    char path[PLATFORM_MAX_PATH],line[PLATFORM_MAX_PATH];BuildPath(Path_SM,path,sizeof(path),"configs/casino_cards_downloads.txt");
    File f=OpenFile(path,"r");if(f==null){LogError("Card download manifest missing");return;}
    bool missing;
    while(f.ReadLine(line,sizeof(line))){TrimString(line);if(!line[0])continue;if(!FileExists(line,true)){LogError("Missing card asset %s",line);missing=true;}else AddFileToDownloadsTable(line);}
    delete f;if(missing)return;
    for(int i=0;i<sizeof(models);i++)if(!PrecacheModel(models[i],true))return;
    for(int i=0;i<sizeof(sounds);i++)if(!PrecacheSound(sounds[i],true))return;
    ready=SeatsPrecache()&&ViewPrecache();nextFrame=0.0;
}
public void OnClientPutInServer(int c){chips[c]=1000;bet[c]=10;previous[c]=0;typing[c]=false;nextUse[c]=0.0;viewBJHold[c]=0.0;blackjack[c].active=false;SDKHook(c,SDKHook_OnTakeDamage,SeatDamage);}
public Action SeatDamage(int c,int &a,int &inf,float &damage,int &type){if(!seatSlot[c])return Plugin_Continue;damage=0.0;return Plugin_Handled;}
public void OnClientDisconnect(int c){seatDiscard[c]=true;SeatStop(c,false);chips[c]=0;typing[c]=false;revision[c]++;}
public void OnMapEnd(){ready=false;for(int t=0;t<TABLES;t++)RemoveTable(t);}
public void OnPluginEnd(){
    ending=true;
    int count=ownedMenus==null?0:ownedMenus.Length;
    LogMessage("CARD_MENU shutdown begin tracked=%d",count);
    while(ownedMenus!=null&&ownedMenus.Length)MenuEnd(view_as<Menu>(ownedMenus.Get(ownedMenus.Length-1)));
    LogMessage("CARD_MENU shutdown complete closed=%d",count);
    delete ownedMenus;
    for(int t=0;t<TABLES;t++)RemoveTable(t);
}
void MenuEnd(Menu m){
    if(ownedMenus==null)return;
    int i=ownedMenus.FindValue(m);if(i<0)return;
    // Cancel with a live handle, after unregistering to prevent recursive End deletion.
    ownedMenus.Erase(i);
    m.Cancel();
    delete m;
}
void SoundAt(int t,int which){int e=Entity(tables[t].body);if(e!=-1)EmitSoundToAll(sounds[which],e,SNDCHAN_AUTO,SNDLEVEL_NORMAL);}
void Shuffle(int deck[52]){for(int i=0;i<52;i++)deck[i]=i;for(int i=51;i>0;i--){int j=GetRandomInt(0,i),v=deck[i];deck[i]=deck[j];deck[j]=v;}}
void CardText(int card,char[] out,int size){
    char suits[][]={"♠","♥","♦","♣"},ranks[][]={"2","3","4","5","6","7","8","9","10","J","Q","K","A"};
    Format(out,size,"%s%s",suits[card/13],ranks[card%13]);
}
void CardsText(const int[] cards,int count,char[] out,int size){out[0]=0;for(int i=0;i<count;i++){char s[16];CardText(cards[i],s,sizeof(s));if(i)StrCat(out,size," ");StrCat(out,size,s);}}
int Owner(int t,int i){int c=GetClientOfUserId(tables[t].users[i]);return c>0&&IsClientInGame(c)?c:0;}
int Seated(int s){for(int c=1;c<=MaxClients;c++)if(seatSlot[c]==s+1&&Player(c))return c;return 0;}
void AddChips(int c,int value){if(c>0){chips[c]+=value;if(chips[c]>MAX_CHIPS)chips[c]=MAX_CHIPS;}}

public Action Setup(int c,int args){
    if(!Admin(c))return Plugin_Handled;
    if(args){char a[8];GetCmdArg(1,a,sizeof(a));if(StrEqual(a,"0")||StrEqual(a,"1")||StrEqual(a,"2"))setupKind[c]=StringToInt(a);}
    Menu m=new Menu(SetupHandler);ownedMenus.Push(m);
    m.SetTitle("카드 테이블 설치 · 가상 칩 시험용\n선택: %s",setupKind[c]==0?"블랙잭":"포커");
    m.AddItem("0","블랙잭 테이블 + 의자 6개 설치");m.AddItem("1","포커(텍사스 홀덤) + 의자 6개 설치");
    m.AddItem("2","포커(5카드 드로) + 의자 6개 설치");
    m.AddItem("remove","바라보는 카드 테이블 삭제");m.AddItem("back","기존 도박 메뉴");m.Display(c,MENU_TIME_FOREVER);return Plugin_Handled;
}
public int SetupHandler(Menu m,MenuAction action,int c,int item){
    if(action==MenuAction_End){MenuEnd(m);return 0;}if(ending||action!=MenuAction_Select||!Admin(c))return 0;
    char key[16];m.GetItem(item,key,sizeof(key));
    if(StrEqual(key,"back")){FakeClientCommandEx(c,"sm_gamble_kind 0");return 0;}
    if(StrEqual(key,"remove")){
        int e=Aim(c,800.0),t=-1;
        for(int j=0;j<TABLES;j++){if(e>MaxClients&&e==Entity(tables[j].body))t=j;for(int i=0;i<6;i++)if(e>MaxClients&&e==Entity(machines[j*6+i].chair))t=j;}
        if(t>=0){RemoveTable(t);PrintToChat(c,"[카드] 테이블·의자 제거. 진행 중 게임은 취소·환불했습니다.");}else PrintToChat(c,"[카드] 테이블 또는 의자를 바라보세요.");
    }else SpawnTable(c,StringToInt(key));
    return 0;
}
int Aim(int c,float distance){float p[3],a[3],v[3],end[3];GetClientEyePosition(c,p);GetClientEyeAngles(c,a);GetAngleVectors(a,v,NULL_VECTOR,NULL_VECTOR);for(int i=0;i<3;i++)end[i]=p[i]+v[i]*distance;Handle tr=TR_TraceRayFilterEx(p,end,MASK_SOLID,RayType_EndPoint,SeatAimTrace,c);int e=TR_DidHit(tr)?TR_GetEntityIndex(tr):-1;delete tr;return e;}
void SpawnTable(int c,int kind){
    if(kind<0||kind>2)return;
    if(!ready||!Player(c)||seatSlot[c]){PrintToChat(c,"[카드] 모델 준비 및 살아 있는 비탑승 상태가 필요합니다.");return;}
    int t=-1;for(int i=0;i<TABLES;i++)if(Entity(tables[i].body)==-1){t=i;break;}
    if(t<0||GetEntityCount()>GetMaxEntities()-160){PrintToChat(c,"[카드] 테이블 또는 엔티티 한도입니다.");return;}
    float eye[3],a[3],p[3],n[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,a);
    Handle tr=TR_TraceRayFilterEx(eye,a,MASK_SOLID,RayType_Infinite,SeatAimTrace,c);
    bool hit=TR_DidHit(tr)&&!TR_StartSolid(tr);TR_GetEndPosition(p,tr);TR_GetPlaneNormal(tr,n);delete tr;
    if(!hit||n[2]<0.9||GetVectorDistance(eye,p)>800.0){PrintToChat(c,"[카드] 가까운 평평한 바닥을 바라보세요.");return;}
    // Check the entire installation volume before creating any entities.
    float mins[3]={-180.0,-135.0,2.0},maxs[3]={180.0,135.0,95.0};
    tr=TR_TraceHullFilterEx(p,p,mins,maxs,MASK_SOLID,SeatAimTrace,c);bool blocked=TR_DidHit(tr)||TR_StartSolid(tr);delete tr;
    if(blocked){PrintToChat(c,"[카드] 테이블과 여섯 의자를 설치할 공간이 부족합니다.");return;}
    tables[t].kind=kind;tables[t].origin=p;tables[t].yaw=0.0;tables[t].dealer=5;
    tables[t].body=Prop(models[kind==0?0:1],true);if(Entity(tables[t].body)==-1)return;
    float angle[3];angle[1]=-90.0;TeleportEntity(Entity(tables[t].body),p,angle,NULL_VECTOR);
    for(int i=0;i<6;i++){
        int s=t*6+i;float rad=DegToRad(30.0+float(i)*60.0),cp[3],end[3],normal[3];cp=p;
        float offset[3];offset[0]=Cosine(rad)*(kind==0?130.0:150.0);offset[1]=Sine(rad)*105.0;
        float distance=GetVectorLength(offset);ScaleVector(offset,(distance-20.0)/distance);
        AddVectors(cp,offset,cp);cp[2]+=32.0;end=cp;end[2]-=64.0;
        tr=TR_TraceRayFilterEx(cp,end,MASK_SOLID,RayType_EndPoint,TraceWorld);
        bool floor=TR_DidHit(tr)&&!TR_StartSolid(tr);TR_GetEndPosition(cp,tr);TR_GetPlaneNormal(tr,normal);delete tr;
        if(!floor||normal[2]<0.9||FloatAbs(cp[2]-p[2])>16.0){RemoveTable(t);PrintToChat(c,"[카드] 의자 아래 바닥이 없어 설치를 취소했습니다.");return;}
        machines[s].origin=cp;machines[s].chairOrigin=cp;
        machines[s].yaw=RadToDeg(ArcTangent2(cp[1]-p[1],cp[0]-p[0]));
        machines[s].chair=Prop(CHAIR_MODEL,true);
        if(Entity(machines[s].chair)==-1){RemoveTable(t);return;}
        angle[1]=machines[s].yaw+90.0;TeleportEntity(Entity(machines[s].chair),cp,angle,NULL_VECTOR);
    }
    PrintToChat(c,"[카드] %s 설치 완료. 테이블/의자를 보고 E 또는 메딕 호출: 착석 / Ctrl: 하차",kind==0?"블랙잭":"포커");
}
void RemoveTable(int t){
    ViewClear(t);
    if(tables[t].phase){for(int i=0;i<6;i++)AddChips(Owner(t,i),tables[t].paid[i]);tables[t].phase=0;}
    for(int s=t*6;s<t*6+6;s++){
        int c=Seated(s);if(c){if(blackjack[c].active){AddChips(c,blackjack[c].wager);blackjack[c].active=false;}SeatStop(c,false);}
        int e=Entity(machines[s].chair);if(e!=-1)RemoveEntity(e);Machine blank;machines[s]=blank;
    }
    int e=Entity(tables[t].body);if(e!=-1)RemoveEntity(e);Table blank;tables[t]=blank;tables[t].dealer=5;
}
public Action Status(int c,int args){int count;for(int t=0;t<TABLES;t++)if(Entity(tables[t].body)!=-1)count++;ReplyToCommand(c,"CasinoCards %s ready=%d tables=%d virtual_chips_only=1 mount_clearance=off medic_call=1",VERSION,ready,count);return Plugin_Handled;}
public Action SelfTest(int c,int args){
    CardRulesTest();int deck[52];
    int menus=ownedMenus.Length;
    Menu probe=new Menu(SetupHandler);ownedMenus.Push(probe);
    MenuEnd(probe);MenuEnd(probe);
    if(ownedMenus.Length!=menus){ReplyToCommand(c,"FAIL menu cleanup");return Plugin_Handled;}
    if(!CardSeatTrace(0,0,0)||CardSeatTrace(1,0,0)){ReplyToCommand(c,"FAIL card seat trace policy");return Plugin_Handled;}
    if(ViewFaceAllowed(123,124,1.0,false)||ViewFaceAllowed(0,123,1.0,false)||ViewFaceAllowed(-1,123,0.0,false)||ViewFaceAllowed(-1,123,1.0,true)||!ViewFaceAllowed(123,123,1.0,false)||!ViewFaceAllowed(-1,124,1.0,false)){ReplyToCommand(c,"FAIL card privacy");return Plugin_Handled;}
    for(int trial=0;trial<100;trial++){Shuffle(deck);bool seen[52];for(int i=0;i<52;i++){if(deck[i]<0||deck[i]>=52||seen[deck[i]]){ReplyToCommand(c,"FAIL shuffle");return Plugin_Handled;}seen[deck[i]]=true;}}
    bool camera=ready&&SeatCameraVerify();
    ReplyToCommand(c,"CasinoCards rules PASS: aces, best-seven, ranking, side-pots, ties, 100 unique-deck shuffles, card privacy; seat_camera=%d",camera);return Plugin_Handled;
}
public Action OpenGame(int c,int args){if(Player(c)&&seatSlot[c])ShowGame(c);else if(c>0)PrintToChat(c,"[카드] 테이블/의자를 보고 E키 또는 메딕 호출로 앉으세요.");return Plugin_Handled;}
public bool CardSeatTrace(int e,int mask,any data){
    if(e==0)return true;
    if(e<=MaxClients)return false;
    for(int t=0;t<TABLES;t++)if(e==Entity(tables[t].body))return true;
    for(int s=0;s<COUNT;s++)if(e==Entity(machines[s].chair))return true;
    return false;
}
bool CardSeatOccupied(int s){
    for(int c=1;c<=MaxClients;c++)if(seatSlot[c]==s+1)return true;
    return false;
}
bool CardSeatUse(int c){
    float eye[3],angles[3],direction[3],end[3];
    GetClientEyePosition(c,eye);GetClientEyeAngles(c,angles);GetAngleVectors(angles,direction,NULL_VECTOR,NULL_VECTOR);
    for(int i=0;i<3;i++)end[i]=eye[i]+direction[i]*120.0;
    Handle tr=TR_TraceRayFilterEx(eye,end,MASK_SOLID,RayType_EndPoint,CardSeatTrace);
    int hit=TR_DidHit(tr)?TR_GetEntityIndex(tr):-1;delete tr;
    if(hit<=MaxClients)return false;
    for(int s=0;s<COUNT;s++)if(hit==Entity(machines[s].chair)){
        if(CardSeatOccupied(s))PrintToChat(c,"[카드] 이미 앉아 있는 의자입니다.");else SeatBegin(c,s);
        return true;
    }
    for(int t=0;t<TABLES;t++)if(hit==Entity(tables[t].body)){
        int best=-1;float distance=999999999.0,origin[3];GetClientAbsOrigin(c,origin);
        for(int i=0;i<6;i++){
            int s=t*6+i;if(Entity(machines[s].chair)==-1||CardSeatOccupied(s))continue;
            float candidate=GetVectorDistance(origin,machines[s].chairOrigin,true);
            if(candidate<distance){distance=candidate;best=s;}
        }
        if(best==-1)PrintToChat(c,"[카드] 빈 의자가 없습니다.");else SeatBegin(c,best);
        return true;
    }
    return false;
}
public Action CardMedicCall(int c,const char[] command,int args){
    if(!ready||!Player(c)||args!=2)return Plugin_Continue;
    char menu[8],item[8];GetCmdArg(1,menu,sizeof(menu));GetCmdArg(2,item,sizeof(item));
    if(!StrEqual(menu,"0")||!StrEqual(item,"0"))return Plugin_Continue;
    if(GetGameTime()<nextUse[c])return seatSlot[c]?Plugin_Handled:Plugin_Continue;
    nextUse[c]=GetGameTime()+0.3;
    if(seatSlot[c]){ShowGame(c);return Plugin_Handled;}
    return CardSeatUse(c)?Plugin_Handled:Plugin_Continue;
}
void Item(Menu m,int c,const char[] action,const char[] label,bool enabled=true){char key[64];Format(key,sizeof(key),"%d:%s",revision[c],action);m.AddItem(key,label,enabled?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);}
void ShowGame(int c){
    if(ending||!Player(c)||!seatSlot[c])return;
    int s=seatSlot[c]-1,t=s/6,i=s%6;char title[1024],hand[256],house[128],label[128];
    revision[c]++;
    Menu m=new Menu(GameHandler);ownedMenus.Push(m);m.Pagination=7;
    if(GetGameTime()<viewBusy[t]||GetGameTime()<viewBJHold[c]||GetGameTime()<viewHold[t]){
        m.SetTitle("카드 배분 / 결과 공개 중\n테이블 위 카드를 확인하세요.\n가상 칩 %d",chips[c]);
        Item(m,c,"refresh","상태 확인");Item(m,c,"leave","일어나기");m.Display(c,MENU_TIME_FOREVER);return;
    }
    if(tables[t].kind==0){
        if(blackjack[c].active){
            CardsText(blackjack[c].hand,blackjack[c].count,hand,sizeof(hand));CardText(blackjack[c].dealer[0],house,sizeof(house));
            Format(title,sizeof(title),"블랙잭 · 가상 칩 %d / 베팅 %d\n내 패: %s = %d\n딜러: %s [숨김]\n선택 제한 30초 / 하차는 포기",chips[c],blackjack[c].wager,hand,BlackjackValue(blackjack[c].hand,blackjack[c].count),house);
            Item(m,c,"hit","히트 (한 장 받기)");Item(m,c,"stand","스탠드");Item(m,c,"double","더블다운",blackjack[c].count==2&&chips[c]>=blackjack[c].wager);
        }else {
            Format(title,sizeof(title),"블랙잭 · 가상 칩 %d / 베팅 %d\n딜러 S17 · 블랙잭 3:2\n스플릿·보험 없음 / 좌석별 독립 게임",chips[c],bet[c]);
            Item(m,c,"deal","베팅 확정 · 카드 받기",chips[c]>=bet[c]);Item(m,c,"plus","베팅 +10",bet[c]<500);Item(m,c,"minus","베팅 -10",bet[c]>10);Item(m,c,"input","베팅 직접 입력 (10~500 / 10단위)");
            Item(m,c,"refill","시험 칩 1000으로 충전",chips[c]<10);
        }
    }else {
        CardsText(tables[t].board,tables[t].shown,house,sizeof(house));
        int pot;for(int k=0;k<6;k++)pot+=tables[t].paid[k];
        hand[0]=0;if(tables[t].phase&&tables[t].users[i]==GetClientUserId(c)){int own[5];for(int j=0;j<5;j++)own[j]=tables[t].hole[i*5+j];CardsText(own,tables[t].kind==2?5:2,hand,sizeof(hand));}
        Format(title,sizeof(title),"%s · 가상 칩 %d\n고정 리밋 10/20 · 블라인드 5/10\n공개: %s\n내 패: %s\n팟: %d / 단계: %d",tables[t].kind==2?"5카드 드로":"텍사스 홀덤",chips[c],house,hand,pot,tables[t].phase);
        if(!tables[t].phase){Item(m,c,"start","앉은 사람들과 시작 (2~6명)");Item(m,c,"refill","시험 칩 1000으로 충전",chips[c]<10);}
        else if(tables[t].actor==i&&tables[t].users[i]==GetClientUserId(c)&&!tables[t].folded[i]){
            if(tables[t].kind==2&&tables[t].phase==2){
                for(int j=0;j<5;j++){char key[8],card[16];Format(key,sizeof(key),"d%d",j);CardText(tables[t].hole[i*5+j],card,sizeof(card));Format(label,sizeof(label),"%s %s",tables[t].drawMask[i]&(1<<j)?"교체":"유지",card);Item(m,c,key,label);}
                Item(m,c,"draw","선택한 카드 교체 확정");
            }else{
            int call=tables[t].current-tables[t].street[i];Format(label,sizeof(label),call>0?"콜 %d (부족하면 올인)":"체크",call);Item(m,c,"call",label);
            int raise=tables[t].phase>=3?20:10;Format(label,sizeof(label),"레이즈 +%d",raise);
            Item(m,c,"raise",label,!tables[t].acted[i]&&tables[t].raises<4&&chips[c]>call&&CanRaise(t,i));Item(m,c,"fold","폴드 (이번 판 포기)");
            }
        }else Item(m,c,"refresh","대기 중 · 상태 새로고침");
    }
    Item(m,c,"leave","일어나기 (진행 중이면 포기)");m.SetTitle("%s",title);m.Display(c,MENU_TIME_FOREVER);
}
public int GameHandler(Menu m,MenuAction action,int c,int item){
    if(action==MenuAction_End){MenuEnd(m);return 0;}
    if(ending||action!=MenuAction_Select||!Player(c)||!seatSlot[c])return 0;
    char key[64],parts[2][32];m.GetItem(item,key,sizeof(key));
    if(ExplodeString(key,":",parts,2,32)!=2||StringToInt(parts[0])!=revision[c]){ShowGame(c);return 0;}
    revision[c]++;int s=seatSlot[c]-1,t=s/6,i=s%6;
    if(StrEqual(parts[1],"leave")){SeatStop(c,true);return 0;}
    if(GetGameTime()<viewBusy[t]||GetGameTime()<viewBJHold[c]||GetGameTime()<viewHold[t]){ShowGame(c);return 0;}
    if(StrEqual(parts[1],"refill")){if(chips[c]<10&&!blackjack[c].active&&!tables[t].phase)chips[c]=1000;}
    else if(tables[t].kind==0){
        if(!blackjack[c].active){
            if(StrEqual(parts[1],"deal"))DealBJ(c);
            else if(StrEqual(parts[1],"plus")&&bet[c]<500)bet[c]+=10;
            else if(StrEqual(parts[1],"minus")&&bet[c]>10)bet[c]-=10;
            else if(StrEqual(parts[1],"input")){typing[c]=true;PrintToChat(c,"[카드] 베팅 10~500을 10단위로 채팅 입력. 취소: !취소");return 0;}
        }else if(StrEqual(parts[1],"hit")){BJDraw(c);if(BlackjackValue(blackjack[c].hand,blackjack[c].count)>=21)FinishBJ(c);}
        else if(StrEqual(parts[1],"stand"))FinishBJ(c);
        else if(StrEqual(parts[1],"double")&&blackjack[c].count==2&&chips[c]>=blackjack[c].wager){chips[c]-=blackjack[c].wager;blackjack[c].wager*=2;BJDraw(c);FinishBJ(c);}
    }else {
        if(StrEqual(parts[1],"start")&&!tables[t].phase)StartPoker(t);
        else if(tables[t].phase&&tables[t].actor==i&&tables[t].users[i]==GetClientUserId(c))PokerAction(t,i,parts[1]);
    }
    if(seatSlot[c])ShowGame(c);return 0;
}
public Action Chat(int c,const char[] cmd,int args){
    if(c<1||!IsClientInGame(c)||!typing[c])return Plugin_Continue;
    char text[128];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);
    if(text[0]=='!'||text[0]=='/'){typing[c]=false;return Plugin_Continue;}
    if(!seatSlot[c]||blackjack[c].active){typing[c]=false;return Plugin_Continue;}
    int n=strlen(text);bool valid=n>0&&n<=3;for(int i=0;i<n;i++)if(text[i]<'0'||text[i]>'9')valid=false;
    int v=StringToInt(text);if(!valid||v<10||v>500||v%10){PrintToChat(c,"[카드] 10~500 / 10단위 숫자를 입력하세요.");return Plugin_Handled;}
    bet[c]=v;typing[c]=false;ShowGame(c);return Plugin_Handled;
}
void DealBJ(int c){
    if(blackjack[c].active||chips[c]<bet[c])return;
    BJ empty;blackjack[c]=empty;blackjack[c].active=true;blackjack[c].wager=bet[c];chips[c]-=bet[c];
    Shuffle(blackjack[c].deck);blackjack[c].count=blackjack[c].dc=2;
    blackjack[c].hand[0]=blackjack[c].deck[0];blackjack[c].dealer[0]=blackjack[c].deck[1];
    blackjack[c].hand[1]=blackjack[c].deck[2];blackjack[c].dealer[1]=blackjack[c].deck[3];blackjack[c].cursor=4;
    blackjack[c].due=GetGameTime()+30.0;SoundAt((seatSlot[c]-1)/6,1);
    ViewBJ(c);
    if(BlackjackValue(blackjack[c].hand,2)==21||BlackjackValue(blackjack[c].dealer,2)==21)FinishBJ(c);
}
void BJDraw(int c){
    if(blackjack[c].count>=12||blackjack[c].cursor>=52){FinishBJ(c);return;}
    blackjack[c].hand[blackjack[c].count++]=blackjack[c].deck[blackjack[c].cursor++];blackjack[c].due=GetGameTime()+30.0;
    ViewBJ(c);
}
void FinishBJ(int c){
    if(!blackjack[c].active)return;blackjack[c].active=false;
    int player=BlackjackValue(blackjack[c].hand,blackjack[c].count);
    bool natural=player==21&&blackjack[c].count==2;
    while(player<=21&&!natural&&BlackjackValue(blackjack[c].dealer,blackjack[c].dc)<17&&blackjack[c].dc<12)
        blackjack[c].dealer[blackjack[c].dc++]=blackjack[c].deck[blackjack[c].cursor++];
    int house=BlackjackValue(blackjack[c].dealer,blackjack[c].dc),reward;
    bool dn=house==21&&blackjack[c].dc==2;
    if(player<=21){if(natural&&!dn)reward=blackjack[c].wager*5/2;else if(natural&&dn)reward=blackjack[c].wager;else if(!dn){if(house>21||player>house)reward=blackjack[c].wager*2;else if(player==house)reward=blackjack[c].wager;}}
    AddChips(c,reward);char cards[160];CardsText(blackjack[c].dealer,blackjack[c].dc,cards,sizeof(cards));
    PrintToChat(c,"[블랙잭] 내 점수 %d / 딜러 %s = %d / 반환 %d (원금 포함)",player,cards,house,reward);
    if(seatSlot[c]){ViewBJ(c,true);viewBJHold[c]=GetGameTime()+5.0;SoundAt((seatSlot[c]-1)/6,natural&&reward>blackjack[c].wager?9:7);}
}

bool CanAct(int t,int i){int c=Owner(t,i);return c>0&&!tables[t].folded[i]&&chips[c]>0;}
bool CanRaise(int t,int i){for(int j=0;j<6;j++)if(j!=i&&CanAct(t,j))return true;return false;}
int NextPlayer(int t,int after){for(int k=1;k<=6;k++){int i=(after+k)%6;if(tables[t].users[i]&&!tables[t].folded[i])return i;}return -1;}
void Pay(int t,int i,int amount){int c=Owner(t,i);if(!c)return;if(amount>chips[c])amount=chips[c];if(amount<0)return;chips[c]-=amount;tables[t].paid[i]+=amount;tables[t].street[i]+=amount;}
void StartPoker(int t){
    if(GetGameTime()<viewHold[t]||GetGameTime()<viewBusy[t])return;
    int count,users[6];for(int i=0;i<6;i++){int c=Seated(t*6+i);if(c&&chips[c]>=10){users[i]=GetClientUserId(c);count++;}}
    if(count<2){for(int i=0;i<6;i++){int c=Seated(t*6+i);if(c)PrintToChat(c,"[포커] 가상 칩 10 이상인 플레이어가 2명 필요합니다.");}return;}
    ViewCollect(t,0,35);viewNextHand[t]=0.0;strcopy(viewLog[t],sizeof(viewLog[]),"NEW HAND / DEALING");
    tables[t].discarded=0;
    tables[t].phase=1;tables[t].cursor=0;tables[t].shown=0;tables[t].current=10;tables[t].raises=0;
    Shuffle(tables[t].deck);
    for(int i=0;i<6;i++){
        tables[t].users[i]=users[i];tables[t].paid[i]=tables[t].street[i]=0;tables[t].folded[i]=users[i]==0;tables[t].pending[i]=users[i]!=0;tables[t].acted[i]=false;
        tables[t].drawMask[i]=0;
        if(users[i])for(int j=0;j<(tables[t].kind==2?5:2);j++)tables[t].hole[i*5+j]=tables[t].deck[tables[t].cursor++];
    }
    tables[t].dealer=NextPlayer(t,tables[t].dealer);
    int small=count==2?tables[t].dealer:NextPlayer(t,tables[t].dealer),big=NextPlayer(t,small);
    Pay(t,small,5);Pay(t,big,10);SoundAt(t,1);Advance(t,big);
}
void PokerAction(int t,int i,const char[] action){
    if(tables[t].kind==2&&tables[t].phase==2){
        if(tables[t].actor!=i||!Owner(t,i)||tables[t].folded[i])return;
        if(action[0]=='d'&&action[1]>='0'&&action[1]<='4'&&action[2]==0){tables[t].drawMask[i]^=1<<(action[1]-'0');return;}
        if(!StrEqual(action,"draw"))return;
        PokerReplace(tables[t].hole,i,tables[t].drawMask[i],tables[t].deck,tables[t].cursor,tables[t].discard,tables[t].discarded);
        tables[t].pending[i]=false;SoundAt(t,0);Advance(t,i);return;
    }
    if(!CanAct(t,i)||tables[t].actor!=i)return;
    int c=Owner(t,i),call=tables[t].current-tables[t].street[i];
    if(StrEqual(action,"fold")){tables[t].folded[i]=true;SoundAt(t,4);}
    else if(StrEqual(action,"call")){Pay(t,i,call);SoundAt(t,call>0?8:6);}
    else if(StrEqual(action,"raise")){
        if(tables[t].acted[i]||tables[t].raises>=4||chips[c]<=call||!CanRaise(t,i))return;
        int step=tables[t].phase>=3?20:10,old=tables[t].current;
        Pay(t,i,call+step);tables[t].current=tables[t].street[i];
        bool full=tables[t].current-old>=step;if(full)tables[t].raises++;
        for(int j=0;j<6;j++)if(j!=i&&CanAct(t,j)){tables[t].pending[j]=true;if(full)tables[t].acted[j]=false;}
        SoundAt(t,2);
    }else return;
    ViewAction(t,c,StrEqual(action,"fold")?"FOLD":(StrEqual(action,"raise")?"RAISE":(call>0?"CALL":"CHECK")));
    tables[t].pending[i]=false;tables[t].acted[i]=true;Advance(t,i);
}
void Advance(int t,int after){
    if(!tables[t].phase)return;
    int active;
    for(int i=0;i<6;i++){if(tables[t].users[i]&&!Owner(t,i))tables[t].folded[i]=true;if(tables[t].users[i]&&!tables[t].folded[i])active++;}
    if(active<=1){SettlePoker(t);return;}
    // At most four streets, so all-in runout cannot loop indefinitely.
    for(int round=0;round<5;round++){
        int actors;for(int i=0;i<6;i++)if(CanAct(t,i))actors++;
        for(int k=1;k<=6;k++){
            int i=(after+k)%6;bool drawing=tables[t].kind==2&&tables[t].phase==2;
            if(!tables[t].pending[i]||tables[t].folded[i]||!Owner(t,i)||(!drawing&&!CanAct(t,i)))continue;
            if(!drawing&&actors==1&&tables[t].street[i]>=tables[t].current){tables[t].pending[i]=false;continue;}
            tables[t].actor=i;tables[t].revision++;tables[t].due=GetGameTime()+30.0;
            int c=Owner(t,i);if(c)EmitSoundToClient(c,sounds[5]);RefreshTable(t);return;
        }
        if(tables[t].phase==(tables[t].kind==2?3:4)){SettlePoker(t);return;}
        if(tables[t].kind==2){
            tables[t].phase++;tables[t].current=0;tables[t].raises=0;
            for(int i=0;i<6;i++){tables[t].street[i]=0;tables[t].pending[i]=tables[t].phase==2?(Owner(t,i)>0&&!tables[t].folded[i]):CanAct(t,i);tables[t].acted[i]=false;}
            after=tables[t].dealer;continue;
        }
        tables[t].phase++;tables[t].cursor++; // Burn one before flop/turn/river.
        int draw=tables[t].phase==2?3:1;
        for(int k=0;k<draw;k++)tables[t].board[tables[t].shown++]=tables[t].deck[tables[t].cursor++];
        tables[t].current=0;tables[t].raises=0;
        for(int i=0;i<6;i++){tables[t].street[i]=0;tables[t].pending[i]=CanAct(t,i);tables[t].acted[i]=false;}
        after=tables[t].dealer;
    }
}
void RefreshTable(int t){if(tables[t].phase)ViewPoker(t);for(int i=0;i<6;i++){int c=Seated(t*6+i);if(c)ShowGame(c);}}
void SettlePoker(int t){
    int ranks[6],awards[6],seven[7],survivors;
    for(int i=0;i<6;i++)if(tables[t].users[i]&&!tables[t].folded[i])survivors++;
    for(int i=0;i<6;i++)if(tables[t].users[i]&&!tables[t].folded[i]){
        if(tables[t].kind==2){int own[5];for(int j=0;j<5;j++)own[j]=tables[t].hole[i*5+j];ranks[i]=PokerFive(own);}
        else if(tables[t].shown==5){seven[0]=tables[t].hole[i*5];seven[1]=tables[t].hole[i*5+1];for(int j=0;j<5;j++)seven[j+2]=tables[t].board[j];ranks[i]=PokerSeven(seven);}
        else ranks[i]=1;
    }
    SplitPots(tables[t].paid,tables[t].folded,ranks,tables[t].dealer,awards);
    int paid,total;for(int i=0;i<6;i++){paid+=tables[t].paid[i];total+=awards[i];}
    if(total!=paid){LogError("Pot conservation failure");for(int i=0;i<6;i++)awards[i]=tables[t].paid[i];}
    tables[t].phase=0;tables[t].actor=-1;
    ViewPoker(t,(tables[t].shown==5||tables[t].kind==2)&&survivors>1);viewHold[t]=GetGameTime()+5.0;
    for(int i=0;i<6;i++){
        int c=Owner(t,i);AddChips(c,awards[i]);
        if(c)PrintToChat(c,"[포커] 이번 판 투입 %d / 반환 %d / 가상 칩 %d",tables[t].paid[i],awards[i],chips[c]);
        if(!tables[t].folded[i]&&(tables[t].shown==5||tables[t].kind==2)&&survivors>1){int own[5];for(int j=0;j<5;j++)own[j]=tables[t].hole[i*5+j];char cards[96],name[64];CardsText(own,tables[t].kind==2?5:2,cards,sizeof(cards));if(c)GetClientName(c,name,sizeof(name));else strcopy(name,sizeof(name),"퇴장한 플레이어");for(int j=0;j<6;j++){int viewer=Seated(t*6+j);if(viewer)PrintToChat(viewer,"[포커 공개] %s: %s / 족보 등급 %d",name,cards,ranks[i]/759375);}}
    }
    for(int i=0;i<6;i++)tables[t].paid[i]=0;
    SoundAt(t,3);RefreshTable(t);
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float velocity[3],float angles[3],int &weapon){
    if(!Player(c)||!ready)return Plugin_Continue;int old=previous[c];previous[c]=buttons;
    if(!seatSlot[c]){if((buttons&IN_USE)&&!(old&IN_USE)&&GetGameTime()>=nextUse[c]){nextUse[c]=GetGameTime()+0.3;CardSeatUse(c);}return Plugin_Continue;}
    if((buttons&IN_DUCK)&&!(old&IN_DUCK)){SeatStop(c,true);if(!seatSlot[c])return Plugin_Continue;}
    if((buttons&IN_ATTACK3)&&!(old&IN_ATTACK3))seatThird[c]=!seatThird[c];
    if((buttons&IN_USE)&&!(old&IN_USE)&&GetGameTime()>=nextUse[c]){nextUse[c]=GetGameTime()+0.3;ShowGame(c);}
    buttons&=~(IN_ATTACK|IN_ATTACK2|IN_ATTACK3|IN_JUMP|IN_DUCK|IN_USE|IN_RELOAD|IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT);buttons|=IN_DUCK;SeatPhysicsHold(c);weapon=0;
    velocity[0]=velocity[1]=velocity[2]=0.0;return Plugin_Changed;
}
public void OnGameFrame(){
    if(!ready||ending)return;SeatsFrame();CasinoHintFrame();float now=GetGameTime();ViewFrame(now);if(now<nextFrame)return;nextFrame=now+0.5;
    for(int t=0;t<TABLES;t++)if(viewBusy[t]>0.0&&now>=viewBusy[t]){
        viewBusy[t]=0.0;for(int i=0;i<6;i++){int c=Seated(t*6+i);if(c)ShowGame(c);}
    }
    for(int c=1;c<=MaxClients;c++)if(seatSlot[c]&&Player(c)){
        if(blackjack[c].active&&now>=blackjack[c].due){FinishBJ(c);ShowGame(c);}
        int t=(seatSlot[c]-1)/6;int seconds;
        if(tables[t].phase)seconds=RoundToCeil(tables[t].due-now);else if(blackjack[c].active)seconds=RoundToCeil(blackjack[c].due-now);
        SetHudTextParams(0.02,0.25,0.7,255,225,100,255);
        char actor[64]="대기";if(tables[t].phase){int p=Owner(t,tables[t].actor);if(p)GetClientName(p,actor,sizeof(actor));}
        ShowHudText(c,4,"[가상 칩] %d\n차례: %s · 남은 시간 %d초\nE/메딕: 메뉴 / Ctrl: 하차 / 휠: 시점",chips[c],actor,seconds>0?seconds:0);
    }
    for(int t=0;t<TABLES;t++)if(tables[t].phase&&now>=tables[t].due){int i=tables[t].actor;if(i>=0){if(tables[t].kind==2&&tables[t].phase==2)PokerAction(t,i,"draw");else if(tables[t].street[i]<tables[t].current)PokerAction(t,i,"fold");else PokerAction(t,i,"call");}}
}
