// Reuse Tower Slots menu lifecycle and installation checks for DON.
int installCount[MAXPLAYERS+1],inputMode[MAXPLAYERS+1];
int testOutcome[MAXPLAYERS+1]; // 0 normal, 1 success, 2 failure; consumed once.
float installSpacing[MAXPLAYERS+1];
ArrayList donMenus;
bool donEnding;
int selectedMachine[MAXPLAYERS+1];
bool DonAdmin(int c){return c>0&&IsClientInGame(c)&&(GetUserFlagBits(c)&(ADMFLAG_GENERIC|ADMFLAG_ROOT))!=0&&CheckCommandAccess(c,"sm_doublenothing",ADMFLAG_GENERIC);}
void DonSetupInit(){
    donMenus=new ArrayList();
    RegAdminCmd("sm_gamble",GambleCommand,ADMFLAG_GENERIC);
    RegAdminCmd("sm_gamble_kind",GambleKindCommand,ADMFLAG_GENERIC);
    RegAdminCmd("sm_gamble_list",GambleListCommand,ADMFLAG_GENERIC);
    RegAdminCmd("sm_doublenothing",SetupCommand,ADMFLAG_GENERIC);
    AddCommandListener(DonChat,"say");AddCommandListener(DonChat,"say_team");
    int n;
    if(!ParseSetting("5",2,n)||n!=5||ParseSetting("4",2,n)||ParseSetting("2001",2,n)
       ||!ParseSetting("32",1,n)||ParseSetting("33",1,n)||ParseSetting("5x",2,n)
       ||FloatAbs(RowOffset(0,2,5.0)+2.5)>0.001||FloatAbs(RowOffset(1,2,5.0)-2.5)>0.001)
       SetFailState("Don setup bounds/spacing selftest failed");
}
public Action DonChat(int c,const char[] command,int argc)
{
    if(donEnding)return Plugin_Continue;
    char text[128];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);
    if(c<1 || !IsClientInGame(c)) return Plugin_Continue;
    if(StrEqual(text,"!도박")||StrEqual(text,"/도박")){if(DonAdmin(c))GambleCommand(c,0);else PrintToChat(c,"[도박] 어드민 전용입니다.");return Plugin_Handled;}
    if(StrEqual(text,"!더블") || StrEqual(text,"!더블오어낫띵") || StrEqual(text,"!더블설치") || StrEqual(text,"/더블")) {
        if(DonAdmin(c)) SetupCommand(c,0);
        else PrintToChat(c,"[더블] 어드민 전용입니다.");
        return Plugin_Handled;
    }
    if(inputMode[c]!=0) {
        if(!DonAdmin(c)) {inputMode[c]=0;return Plugin_Continue;}
        if(StrEqual(text,"!취소") || StrEqual(text,"취소")) {inputMode[c]=0;ShowSetup(c);return Plugin_Handled;}
        if(text[0]=='!' || text[0]=='/') {inputMode[c]=0;return Plugin_Continue;}
        int number;
        if(!ParseSetting(text,inputMode[c],number)) {PrintToChat(c,"[더블] 개수 1~32 / 중심 간격 5~2000의 정수를 입력하세요. 취소: !취소");return Plugin_Handled;}
        if(inputMode[c]==1) installCount[c]=number;else installSpacing[c]=float(number);
        inputMode[c]=0;ShowSetup(c);return Plugin_Handled;
    }
    return Plugin_Continue;
}
bool ParseSetting(const char[] text,int mode,int &number)
{
    int length=strlen(text);if(length==0 || length>4) return false;
    for(int i=0;i<length;i++) if(text[i]<'0' || text[i]>'9') return false;
    number=StringToInt(text);return mode==1?(number>=1 && number<=32):(number>=5 && number<=2000);
}
public Action SetupCommand(int c,int args)
{
    if(!donEnding && DonAdmin(c)) {inputMode[c]=0;ShowSetup(c);}return Plugin_Handled;
}
void DonMenuEnd(Menu menu){
    if(donEnding)return;
    int index=donMenus.FindValue(menu);
    if(index==-1)return;
    donMenus.Erase(index);delete menu;
}
void DonMenusShutdown(){
    donEnding=true;
    // Destroy while callbacks are still alive; End callbacks must not delete twice.
    while(donMenus!=null && donMenus.Length>0){
        int last=donMenus.Length-1;Menu menu=view_as<Menu>(donMenus.Get(last));
        donMenus.Erase(last);menu.Cancel();delete menu;
    }
    delete donMenus;
}
void ShowSetup(int c)
{
    if(donEnding||!DonAdmin(c))return;
    if(installCount[c]==0) {installCount[c]=1;installSpacing[c]=32.0;}
    Menu menu=new Menu(SetupHandler);donMenus.Push(menu);menu.SetTitle("도박 기계 설치 (중앙 기준 한 줄)");
    menu.AddItem("kind","설치할 기계: 더블 앤 낫띵");
    char label[96];Format(label,sizeof(label),"설치 개수: %d대",installCount[c]);menu.AddItem("count",label);
    Format(label,sizeof(label),"중심 간격: %.0f 유닛",installSpacing[c]);menu.AddItem("spacing",label);
    menu.AddItem("spawn","설정한 개수로 묶음 설치");menu.AddItem("delete","바라보는 더블 오어 낫띵 삭제");
    menu.AddItem("all","더블 오어 낫띵 모두 삭제");menu.AddItem("test","확률 조작 테스트 (내 다음 1회)");menu.Display(c,MENU_TIME_FOREVER);
}
public int SetupHandler(Menu menu,MenuAction action,int c,int item)
{
    if(action==MenuAction_End) {DonMenuEnd(menu);return 0;}
    if(donEnding)return 0;
    if(action!=MenuAction_Select || !DonAdmin(c)) return 0;
    char key[16];menu.GetItem(item,key,sizeof(key));
    if(StrEqual(key,"kind")) {ShowMachineKind(c);
    } else if(StrEqual(key,"count") || StrEqual(key,"spacing")) {
        inputMode[c]=StrEqual(key,"count")?1:2;
        PrintToChat(c,inputMode[c]==1?"[더블] 설치 개수 1~32를 채팅에 입력하세요. 취소: !취소":"[더블] 중심 간격 5~2000 유닛을 채팅에 입력하세요. 취소: !취소");
    } else if(StrEqual(key,"test")) {ShowTest(c);
    } else if(StrEqual(key,"all")) {
        Menu confirm=new Menu(ConfirmHandler);donMenus.Push(confirm);confirm.SetTitle("이 플러그인의 더블 오어 낫띵을 모두 삭제할까요?");
        confirm.AddItem("yes","모두 삭제");confirm.AddItem("no","취소");confirm.Display(c,MENU_TIME_FOREVER);
    } else {
        if(StrEqual(key,"spawn")) SpawnBatch(c,installCount[c],installSpacing[c]);else RemoveAim(c,0);
        ShowSetup(c);
    }
    return 0;
}
public int ConfirmHandler(Menu menu,MenuAction action,int c,int item)
{
    if(action==MenuAction_End) {DonMenuEnd(menu);return 0;}
    if(donEnding)return 0;
    if(action==MenuAction_Select && DonAdmin(c)) {
        if(item==0) {int count;for(int s=0;s<COUNT;s++) {if((Entity(machines[s].body)!=-1)) count++;RemoveMachine(s);}PrintToChat(c,"[더블] %d대 삭제 완료.",count);}
        ShowSetup(c);
    }
    return 0;
}
float RowOffset(int index,int count,float spacing) {return (float(index)-float(count-1)*0.5)*spacing;}
void ShowTest(int c){
    if(donEnding||!DonAdmin(c))return;
    Menu menu=new Menu(TestHandler);donMenus.Push(menu);
    menu.SetTitle("확률 조작 테스트: 내 다음 1회\n본인의 다음 1회만 적용 / 기본 성공 확률 50%");
    char labels[][]={"성공 (두 배)","실패 (0)"};
    for(int i=0;i<2;i++){char key[8];IntToString(i+1,key,sizeof(key));menu.AddItem(key,labels[i]);}
    menu.AddItem("0","테스트 취소 / 정상 확률");menu.ExitBackButton=true;menu.Display(c,MENU_TIME_FOREVER);
}
public int TestHandler(Menu menu,MenuAction action,int c,int item){
    if(action==MenuAction_End) {DonMenuEnd(menu);return 0;}
    if(donEnding)return 0;
    if(!DonAdmin(c))return 0;
    if(action==MenuAction_Cancel&&item==MenuCancel_ExitBack){ShowSetup(c);return 0;}
    if(action!=MenuAction_Select)return 0;
    char key[8],label[64];menu.GetItem(item,key,sizeof(key),_,label,sizeof(label));
    int value=StringToInt(key);if(value<0||value>2)return 0;
    testOutcome[c]=value;PrintToChat(c,"[더블 테스트] %s. 본인이 다음에 돌리는 1회만 적용됩니다.",label);ShowSetup(c);return 0;
}
public bool InstallTrace(int e,int mask,any c){return e==0||e>MaxClients;}
void SpawnBatch(int c,int count,float spacing)
{
    if(!DonAdmin(c))return;
    if(!Player(c) || !ready) {ReplyToCommand(c,"[더블] 살아 있는 플레이어와 준비된 모델이 필요합니다.");return;}
    float eye[3],ang[3],hit[3],normal[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,ang);
    Handle tr=TR_TraceRayFilterEx(eye,ang,MASK_SOLID,RayType_Infinite,InstallTrace,c);
    bool found=TR_DidHit(tr);TR_GetEndPosition(hit,tr);TR_GetPlaneNormal(tr,normal);delete tr;
    if(!found || normal[2]<0.65 || GetVectorDistance(eye,hit)>800.0) {ReplyToCommand(c,"[더블] 800유닛 이내의 평평한 바닥을 바라봐 주세요.");return;}
    int available;for(int s=0;s<COUNT;s++) if(!(Entity(machines[s].body)!=-1)) available++;
    if(count<1 || count>available || GetEntityCount()+count*22>GetMaxEntities()-32) {ReplyToCommand(c,"[더블] 설치 한도 또는 엔티티 여유가 부족합니다. 남은 슬롯: %d",available);return;}
    float positions[COUNT][3],r=DegToRad(ang[1]);
    float mins[3]={-23.0,-23.0,1.0},maxs[3]={23.0,23.0,84.0};
    for(int i=0;i<count;i++) {
        float start[3],end[3];start=hit;float offset=RowOffset(i,count,spacing);
        start[0]+=Sine(r)*offset;start[1]-=Cosine(r)*offset;start[2]+=50.0;end=start;end[2]-=100.0;
        tr=TR_TraceRayFilterEx(start,end,MASK_SOLID,RayType_EndPoint,InstallTrace,c);
        found=TR_DidHit(tr) && !TR_StartSolid(tr);TR_GetEndPosition(positions[i],tr);TR_GetPlaneNormal(tr,normal);delete tr;
        if(!found || normal[2]<0.65 || FloatAbs(positions[i][2]-hit[2])>48.0) {ReplyToCommand(c,"[더블] %d번째 위치에 48유닛 이내의 안전한 바닥이 없어 설치를 취소했습니다.",i+1);return;}
        positions[i][2]+=0.1;
        bool blocked=true;float floorZ=positions[i][2];
        for(int step=0;step<=6;step++){
            positions[i][2]=floorZ+float(step)*8.0;
            if(FloatAbs(positions[i][2]-hit[2])>48.1)break;
            tr=TR_TraceHullFilterEx(positions[i],positions[i],mins,maxs,MASK_SOLID,InstallTrace,c);
            blocked=TR_StartSolid(tr)||TR_AllSolid(tr)||TR_DidHit(tr);delete tr;if(!blocked)break;
        }
        if(blocked) {ReplyToCommand(c,"[더블] %d번째 설치 공간이 부족해 전체 설치를 취소했습니다.",i+1);return;}
    }
    int created[COUNT];
    for(int i=0;i<count;i++) {
        created[i]=CreateMachine(positions[i],ang[1]+180.0);
        if(created[i]<0) {for(int k=0;k<i;k++) RemoveMachine(created[k]);ReplyToCommand(c,"[더블] 생성 실패. 이번 설치만 되돌렸습니다.");return;}
    }
    PrintToChat(c,"[더블] %d대 설치 완료 / 중심 간격 %.0f 유닛. 조작부를 보고 E키를 누르세요.",count,spacing);
}

public int CreateMachine(const float point[3],float yaw){
    int s=-1;for(int i=0;i<COUNT;i++)if(Entity(machines[i].body)==-1){s=i;break;}
    if(s<0)return -1;
    machines[s].origin=point;machines[s].yaw=yaw;
    if(!CreateParts(s)){RemoveMachine(s);return -1;}return s;
}


void ShowMachineKind(int c){
    if(donEnding||!DonAdmin(c))return;
    Menu menu=new Menu(MachineKindHandler);donMenus.Push(menu);
    menu.SetTitle("설치할 기계 종류");menu.AddItem("0","더블 앤 낫띵");menu.AddItem("1","다이아몬드 슬롯머신");menu.AddItem("2","블랙잭 · 의자 테이블");menu.AddItem("3","포커 · 텍사스 홀덤");
    menu.AddItem("4","포커 · 5카드 드로");menu.AddItem("5","Grand Quest");menu.AddItem("6","Wheel of Money");menu.AddItem("7","비디오 포커");menu.AddItem("8","비디오 블랙잭");menu.AddItem("9","키노");menu.AddItem("10","Planet Bingo");menu.AddItem("11","Silver Saddles 경마");
    menu.ExitBackButton=true;menu.Display(c,MENU_TIME_FOREVER);
}
public Action GambleListCommand(int c,int args){if(!donEnding&&DonAdmin(c)){inputMode[c]=0;ShowMachineKind(c);}return Plugin_Handled;}
public int MachineKindHandler(Menu menu,MenuAction action,int c,int item){
    if(action==MenuAction_End){DonMenuEnd(menu);return 0;}
    if(donEnding||!DonAdmin(c))return 0;
    if(action==MenuAction_Cancel&&item==MenuCancel_ExitBack){ShowSetup(c);return 0;}
    if(action!=MenuAction_Select)return 0;
    char key[8];menu.GetItem(item,key,sizeof(key));int kind=StringToInt(key);if(kind<0||kind>11)return 0;
    inputMode[c]=0;testOutcome[c]=0;
    if(GetCommandFlags("sm_gamble_kind")==INVALID_FCVAR_FLAGS){PrintToChat(c,"[도박] 통합 메뉴 플러그인이 준비되지 않았습니다.");return 0;}
    FakeClientCommandEx(c,"sm_gamble_kind %d",kind);return 0;
}

public Action GambleCommand(int c,int args){
    if(donEnding||!DonAdmin(c))return Plugin_Handled;
    inputMode[c]=0;
    if(selectedMachine[c]==0)ShowSetup(c);
    else if(selectedMachine[c]>=5){
        if(GetCommandFlags("sm_casinoextra")!=INVALID_FCVAR_FLAGS)FakeClientCommandEx(c,"sm_casinoextra %d",selectedMachine[c]-5);
        else PrintToChat(c,"[도박] 추가 카지노 플러그인이 준비되지 않았습니다.");
    }
    else if(selectedMachine[c]>=2){
        if(GetCommandFlags("sm_cardtable")!=INVALID_FCVAR_FLAGS)FakeClientCommandEx(c,"sm_cardtable %d",selectedMachine[c]-2);
        else PrintToChat(c,"[도박] 카드 테이블 플러그인이 준비되지 않았습니다.");
    }
    else if(GetCommandFlags("sm_slotmachine")!=INVALID_FCVAR_FLAGS)FakeClientCommandEx(c,"sm_slotmachine");
    else PrintToChat(c,"[도박] 다이아몬드 슬롯머신 플러그인이 준비되지 않았습니다.");
    return Plugin_Handled;
}
public Action GambleKindCommand(int c,int args){
    if(donEnding||!DonAdmin(c)||args!=1)return Plugin_Handled;
    char key[8];GetCmdArg(1,key,sizeof(key));
    int kind=StringToInt(key);char valid[8];IntToString(kind,valid,sizeof(valid));
    if(!StrEqual(key,valid)||kind<0||kind>11)return Plugin_Handled;
    selectedMachine[c]=kind;return GambleCommand(c,0);
}
