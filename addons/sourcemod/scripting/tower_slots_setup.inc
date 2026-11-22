// Installation UI retained from slot_machine_test; machines are now Tower Slots.
int installCount[MAXPLAYERS+1],inputMode[MAXPLAYERS+1];
int testOutcome[MAXPLAYERS+1]; // Zero = normal; selected category + 1 is consumed once.
float installSpacing[MAXPLAYERS+1];
ArrayList slotMenus;
bool slotEnding;
bool SlotAdmin(int c){return c>0&&IsClientInGame(c)&&(GetUserFlagBits(c)&(ADMFLAG_GENERIC|ADMFLAG_ROOT))!=0&&CheckCommandAccess(c,"sm_slotmachine",ADMFLAG_GENERIC);}
void SlotSetupInit(){
    slotMenus=new ArrayList();
    RegAdminCmd("sm_slotmachine",SetupCommand,ADMFLAG_GENERIC);
    RegAdminCmd("sm_slotmachine_status",Status,ADMFLAG_GENERIC);
    AddCommandListener(SlotChat,"say");AddCommandListener(SlotChat,"say_team");
    int n;
    if(!ParseSetting("5",2,n)||n!=5||ParseSetting("4",2,n)||ParseSetting("2001",2,n)
       ||!ParseSetting("64",1,n)||ParseSetting("65",1,n)||ParseSetting("5x",2,n)
       ||FloatAbs(RowOffset(0,2,5.0)+2.5)>0.001||FloatAbs(RowOffset(1,2,5.0)-2.5)>0.001)
       SetFailState("Slot setup bounds/spacing selftest failed");
}
public Action SlotChat(int c,const char[] command,int argc)
{
    if(slotEnding)return Plugin_Continue;
    char text[128];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);
    if(c<1 || !IsClientInGame(c)) return Plugin_Continue;
    if(StrEqual(text,"!슬롯머신") || StrEqual(text,"/슬롯머신")) {
        if(SlotAdmin(c)) SetupCommand(c,0);
        else PrintToChat(c,"[슬롯] 어드민 전용입니다.");
        return Plugin_Handled;
    }
    if(inputMode[c]!=0) {
        if(!SlotAdmin(c)) {inputMode[c]=0;return Plugin_Continue;}
        if(StrEqual(text,"!취소") || StrEqual(text,"취소")) {inputMode[c]=0;ShowSetup(c);return Plugin_Handled;}
        if(text[0]=='!' || text[0]=='/') {inputMode[c]=0;return Plugin_Continue;}
        int number;
        if(!ParseSetting(text,inputMode[c],number)) {PrintToChat(c,"[슬롯] 개수 1~64 / 중심 간격 5~2000의 정수를 입력하세요. 취소: !취소");return Plugin_Handled;}
        if(inputMode[c]==1) installCount[c]=number;else installSpacing[c]=float(number);
        inputMode[c]=0;ShowSetup(c);return Plugin_Handled;
    }
    return Plugin_Continue;
}
bool ParseSetting(const char[] text,int mode,int &number)
{
    int length=strlen(text);if(length==0 || length>4) return false;
    for(int i=0;i<length;i++) if(text[i]<'0' || text[i]>'9') return false;
    number=StringToInt(text);return mode==1?(number>=1 && number<=64):(number>=5 && number<=2000);
}
public Action SetupCommand(int c,int args)
{
    if(!slotEnding && SlotAdmin(c)) {inputMode[c]=0;ShowSetup(c);}return Plugin_Handled;
}
void SlotMenuEnd(Menu menu){
    if(slotEnding)return;
    int index=slotMenus.FindValue(menu);
    if(index==-1)return;
    slotMenus.Erase(index);delete menu;
}
void SlotMenusShutdown(){
    slotEnding=true;
    // Destroy while callbacks are still alive; End callbacks must not delete twice.
    while(slotMenus!=null && slotMenus.Length>0){
        int last=slotMenus.Length-1;Menu menu=view_as<Menu>(slotMenus.Get(last));
        slotMenus.Erase(last);delete menu;
    }
    delete slotMenus;
}
void ShowSetup(int c)
{
    if(slotEnding||!SlotAdmin(c))return;
    if(installCount[c]==0) {installCount[c]=1;installSpacing[c]=32.0;}
    Menu menu=new Menu(SetupHandler);slotMenus.Push(menu);menu.SetTitle("도박 기계 설치 (중앙 기준 한 줄)");
    menu.AddItem("kind","설치할 기계: 다이아몬드 슬롯머신");
    char label[96];Format(label,sizeof(label),"설치 개수: %d대",installCount[c]);menu.AddItem("count",label);
    Format(label,sizeof(label),"중심 간격: %.0f 유닛",installSpacing[c]);menu.AddItem("spacing",label);
    menu.AddItem("spawn","설정한 개수로 묶음 설치");menu.AddItem("delete","바라보는 슬롯머신 삭제");
    menu.AddItem("all","슬롯머신 모두 삭제");menu.AddItem("test","확률 조작 테스트 (내 다음 1회)");menu.Display(c,MENU_TIME_FOREVER);
}
public int SetupHandler(Menu menu,MenuAction action,int c,int item)
{
    if(action==MenuAction_End) {SlotMenuEnd(menu);return 0;}
    if(slotEnding)return 0;
    if(action!=MenuAction_Select || !SlotAdmin(c)) return 0;
    char key[16];menu.GetItem(item,key,sizeof(key));
    if(StrEqual(key,"kind")) {ShowMachineKind(c);
    } else if(StrEqual(key,"count") || StrEqual(key,"spacing")) {
        inputMode[c]=StrEqual(key,"count")?1:2;
        PrintToChat(c,inputMode[c]==1?"[슬롯] 설치 개수 1~64를 채팅에 입력하세요. 취소: !취소":"[슬롯] 중심 간격 5~2000 유닛을 채팅에 입력하세요. 취소: !취소");
    } else if(StrEqual(key,"test")) {ShowTest(c);
    } else if(StrEqual(key,"all")) {
        Menu confirm=new Menu(ConfirmHandler);slotMenus.Push(confirm);confirm.SetTitle("이 플러그인의 슬롯머신을 모두 삭제할까요?");
        confirm.AddItem("yes","모두 삭제");confirm.AddItem("no","취소");confirm.Display(c,MENU_TIME_FOREVER);
    } else {
        if(StrEqual(key,"spawn")) SpawnBatch(c,installCount[c],installSpacing[c]);else DeleteCommand(c,0);
        ShowSetup(c);
    }
    return 0;
}
public int ConfirmHandler(Menu menu,MenuAction action,int c,int item)
{
    if(action==MenuAction_End) {SlotMenuEnd(menu);return 0;}
    if(slotEnding)return 0;
    if(action==MenuAction_Select && SlotAdmin(c)) {
        if(item==0) {int count;for(int s=0;s<COUNT;s++) {if((Entity(machines[s].body)!=-1)) count++;Remove(s);}PrintToChat(c,"[슬롯] %d대 삭제 완료.",count);}
        ShowSetup(c);
    }
    return 0;
}
float RowOffset(int index,int count,float spacing) {return (float(index)-float(count-1)*0.5)*spacing;}
void ShowTest(int c){
    if(slotEnding||!SlotAdmin(c))return;
    Menu menu=new Menu(TestHandler);slotMenus.Push(menu);
    menu.SetTitle("확률 조작 테스트: 내 다음 1회\n공용 누적금·기존 확률 변경 없음");
    char labels[][]={"다이아 3개 (잭팟)","체리 3개","수박 3개","오렌지 3개","포도 3개","BAR 3개","다이아 2개","다이아 1개","꽝"};
    for(int i=0;i<9;i++){char key[8];IntToString(i+1,key,sizeof(key));menu.AddItem(key,labels[i]);}
    menu.AddItem("0","테스트 취소 / 정상 확률");menu.ExitBackButton=true;menu.Display(c,MENU_TIME_FOREVER);
}
public int TestHandler(Menu menu,MenuAction action,int c,int item){
    if(action==MenuAction_End) {SlotMenuEnd(menu);return 0;}
    if(slotEnding)return 0;
    if(!SlotAdmin(c))return 0;
    if(action==MenuAction_Cancel&&item==MenuCancel_ExitBack){ShowSetup(c);return 0;}
    if(action!=MenuAction_Select)return 0;
    char key[8],label[64];menu.GetItem(item,key,sizeof(key),_,label,sizeof(label));
    int value=StringToInt(key);if(value<0||value>9)return 0;
    testOutcome[c]=value;PrintToChat(c,"[슬롯 테스트] %s. 본인이 다음에 돌리는 1회만 적용됩니다.",label);ShowSetup(c);return 0;
}
public bool InstallTrace(int e,int mask,any c){return e==0||e>MaxClients;}
void SpawnBatch(int c,int count,float spacing)
{
    if(!SlotAdmin(c))return;
    if(!Player(c) || !ready) {ReplyToCommand(c,"[슬롯] 살아 있는 플레이어와 준비된 모델이 필요합니다.");return;}
    float eye[3],ang[3],hit[3],normal[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,ang);
    Handle tr=TR_TraceRayFilterEx(eye,ang,MASK_SOLID,RayType_Infinite,InstallTrace,c);
    bool found=TR_DidHit(tr);TR_GetEndPosition(hit,tr);TR_GetPlaneNormal(tr,normal);delete tr;
    if(!found || normal[2]<0.65 || GetVectorDistance(eye,hit)>800.0) {ReplyToCommand(c,"[슬롯] 800유닛 이내의 평평한 바닥을 바라봐 주세요.");return;}
    int available;for(int s=0;s<COUNT;s++) if(!(Entity(machines[s].body)!=-1)) available++;
    if(count<1 || count>available || GetEntityCount()+count*(16+WIN_FX_COUNT)>GetMaxEntities()-32) {ReplyToCommand(c,"[슬롯] 설치 한도 또는 엔티티 여유가 부족합니다. 남은 슬롯: %d",available);return;}
    float positions[COUNT][3],r=DegToRad(ang[1]);
    float mins[3]={-30.0,-30.0,1.0},maxs[3]={30.0,30.0,145.0};
    for(int i=0;i<count;i++) {
        float start[3],end[3];start=hit;float offset=RowOffset(i,count,spacing);
        start[0]+=Sine(r)*offset;start[1]-=Cosine(r)*offset;start[2]+=50.0;end=start;end[2]-=100.0;
        tr=TR_TraceRayFilterEx(start,end,MASK_SOLID,RayType_EndPoint,InstallTrace,c);
        found=TR_DidHit(tr) && !TR_StartSolid(tr);TR_GetEndPosition(positions[i],tr);TR_GetPlaneNormal(tr,normal);delete tr;
        if(!found || normal[2]<0.65 || FloatAbs(positions[i][2]-hit[2])>48.0) {ReplyToCommand(c,"[슬롯] %d번째 위치에 48유닛 이내의 안전한 바닥이 없어 설치를 취소했습니다.",i+1);return;}
        positions[i][2]+=0.1;
        bool blocked=true;float floorZ=positions[i][2];
        for(int step=0;step<=6;step++){
            positions[i][2]=floorZ+float(step)*8.0;
            if(FloatAbs(positions[i][2]-hit[2])>48.1)break;
            tr=TR_TraceHullFilterEx(positions[i],positions[i],mins,maxs,MASK_SOLID,InstallTrace,c);
            blocked=TR_StartSolid(tr)||TR_AllSolid(tr)||TR_DidHit(tr);delete tr;if(!blocked)break;
        }
        if(blocked) {ReplyToCommand(c,"[슬롯] %d번째 설치 공간이 부족해 전체 설치를 취소했습니다.",i+1);return;}
    }
    int created[COUNT];
    for(int i=0;i<count;i++) {
        created[i]=CreateMachine(positions[i],ang[1]+180.0);
        if(created[i]<0) {for(int k=0;k<i;k++) Remove(created[k]);ReplyToCommand(c,"[슬롯] 생성 실패. 이번 설치만 되돌렸습니다.");return;}
    }
    PrintToChat(c,"[슬롯] %d대 설치 완료 / 중심 간격 %.0f 유닛. 조작부를 보고 E키를 누르세요.",count,spacing);
}

public bool TraceFilter(int ent,int mask,any client){return ent!=client;}
public Action DeleteCommand(int c,int args){
    if(!Player(c))return Plugin_Handled;
    float eye[3],angles[3];SeatAim(c,eye,angles);
    Handle tr=TR_TraceRayFilterEx(eye,angles,MASK_SOLID,RayType_Infinite,TraceFilter,c);
    int e=TR_DidHit(tr)?TR_GetEntityIndex(tr):-1;delete tr;
    int found=-1;
    for(int s=0;s<COUNT&&e>MaxClients;s++){
        if(e==Entity(machines[s].body)||e==Entity(machines[s].chair)||e==Entity(machines[s].highlight))found=s;
        for(int i=0;i<3;i++)if(e==Entity(machines[s].reel[i]))found=s;
        for(int i=0;i<9;i++)if(e==Entity(machines[s].digits[i]))found=s;
        if(found!=-1)break;
    }
    if(found==-1)ReplyToCommand(c,"[슬롯] 삭제할 슬롯머신이나 의자를 바라봐 주세요.");
    else {Remove(found);ReplyToCommand(c,"[슬롯] 바라보는 슬롯머신과 의자를 삭제했습니다.");}
    return Plugin_Handled;
}


void ShowMachineKind(int c){
    if(slotEnding||!SlotAdmin(c))return;
    if(GetCommandFlags("sm_gamble_list")!=INVALID_FCVAR_FLAGS){inputMode[c]=0;FakeClientCommandEx(c,"sm_gamble_list");return;}
    Menu menu=new Menu(MachineKindHandler);slotMenus.Push(menu);
    menu.SetTitle("설치할 기계 종류");menu.AddItem("0","더블 앤 낫띵");menu.AddItem("1","다이아몬드 슬롯머신");menu.AddItem("2","블랙잭 · 의자 테이블");menu.AddItem("3","포커 · 텍사스 홀덤");menu.ExitBackButton=true;menu.Display(c,MENU_TIME_FOREVER);
}
public int MachineKindHandler(Menu menu,MenuAction action,int c,int item){
    if(action==MenuAction_End){SlotMenuEnd(menu);return 0;}
    if(slotEnding||!SlotAdmin(c))return 0;
    if(action==MenuAction_Cancel&&item==MenuCancel_ExitBack){ShowSetup(c);return 0;}
    if(action!=MenuAction_Select)return 0;
    char key[8];menu.GetItem(item,key,sizeof(key));int kind=StringToInt(key);if(kind<0||kind>3)return 0;
    inputMode[c]=0;testOutcome[c]=0;
    if(GetCommandFlags("sm_gamble_kind")==INVALID_FCVAR_FLAGS){PrintToChat(c,"[도박] 통합 메뉴 플러그인이 준비되지 않았습니다.");return 0;}
    FakeClientCommandEx(c,"sm_gamble_kind %d",kind);return 0;
}
