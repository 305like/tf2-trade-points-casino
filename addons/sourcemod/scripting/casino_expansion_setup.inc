// Same centered-row placement and one-shot admin tests as the existing casino machines.
int extraKind[MAXPLAYERS+1],extraCount[MAXPLAYERS+1],extraInput[MAXPLAYERS+1],extraTest[MAXPLAYERS+1];
float extraSpacing[MAXPLAYERS+1];
void ExtraSetup(int c){
    if(ending||!Admin(c))return;
    if(extraCount[c]==0){extraCount[c]=1;extraSpacing[c]=80.0;}
    Menu m=NewMenu(ExtraSetupHandler);char label[128];m.SetTitle("카지노 설치 · 중앙 기준 한 줄 / 시험 칩");
    Format(label,sizeof(label),"설치할 기계: %s",names[extraKind[c]]);m.AddItem("kind",label);
    Format(label,sizeof(label),"설치 개수: %d대",extraCount[c]);m.AddItem("count",label);
    Format(label,sizeof(label),"중심 간격: %.0f 유닛",extraSpacing[c]);m.AddItem("spacing",label);
    m.AddItem("spawn","설정한 개수로 묶음 설치");m.AddItem("remove","바라보는 기계 삭제");
    m.AddItem("test","확률 조작 테스트 (내 다음 슬롯 1회)",extraKind[c]<=1?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
    m.Display(c,MENU_TIME_FOREVER);
}
public int ExtraSetupHandler(Menu m,MenuAction a,int c,int item){
    if(a==MenuAction_End){EndMenu(m);return 0;}if(ending||a!=MenuAction_Select||!Admin(c))return 0;
    char key[16];m.GetItem(item,key,sizeof(key));
    if(StrEqual(key,"kind")){if(GetCommandFlags("sm_gamble_list")!=INVALID_FCVAR_FLAGS){extraInput[c]=0;FakeClientCommandEx(c,"sm_gamble_list");return 0;}Menu kinds=NewMenu(ExtraKindHandler);kinds.SetTitle("설치할 추가 카지노 기계");for(int i=0;i<7;i++){char id[8];IntToString(i,id,sizeof(id));kinds.AddItem(id,names[i]);}kinds.Display(c,MENU_TIME_FOREVER);return 0;}
    if(StrEqual(key,"count")||StrEqual(key,"spacing")){extraInput[c]=StrEqual(key,"count")?1:2;PrintToChat(c,"[카지노] %s 숫자를 채팅에 입력하세요. 취소: !취소",extraInput[c]==1?"개수 1~12":"중심 간격 5~2000");return 0;}
    if(StrEqual(key,"test")){ExtraTestMenu(c);return 0;}
    if(StrEqual(key,"spawn"))ExtraBatch(c);
    if(StrEqual(key,"remove")){int e=GetClientAimTarget(c,false);for(int g=0;g<GAMES;g++)if(e>MaxClients&&(e==Entity(games[g].body)||e==Entity(games[g].stand))){Remove(g);break;}}
    ExtraSetup(c);return 0;
}
public int ExtraKindHandler(Menu m,MenuAction a,int c,int item){
    if(a==MenuAction_End){EndMenu(m);return 0;}if(ending||a!=MenuAction_Select||!Admin(c))return 0;
    char key[8];m.GetItem(item,key,sizeof(key));int kind=StringToInt(key);if(kind<0||kind>=7)return 0;
    extraKind[c]=kind;extraInput[c]=0;
    if(GetCommandFlags("sm_gamble_kind")!=INVALID_FCVAR_FLAGS)FakeClientCommandEx(c,"sm_gamble_kind %d",kind+5);else ExtraSetup(c);return 0;
}
bool ExtraNumber(const char[] text,int mode,int &value){
    int n=strlen(text);if(n<1||n>4)return false;
    for(int i=0;i<n;i++)if(text[i]<'0'||text[i]>'9')return false;
    value=StringToInt(text);return mode==1?(value>=1&&value<=GAMES):(value>=5&&value<=2000);
}
public Action ExtraChat(int c,const char[] cmd,int args){
    if(ending||c<1||c>MaxClients||!extraInput[c])return Plugin_Continue;
    if(!Admin(c)){extraInput[c]=0;return Plugin_Continue;}
    char text[128];GetCmdArgString(text,sizeof(text));StripQuotes(text);TrimString(text);
    if(StrEqual(text,"!취소")||StrEqual(text,"취소")){extraInput[c]=0;ExtraSetup(c);return Plugin_Handled;}
    if(text[0]=='!'||text[0]=='/'){extraInput[c]=0;return Plugin_Continue;}
    int n;if(!ExtraNumber(text,extraInput[c],n)){PrintToChat(c,"[카지노] 개수 1~12 / 간격 5~2000 정수만 가능합니다.");return Plugin_Handled;}
    if(extraInput[c]==1)extraCount[c]=n;else extraSpacing[c]=float(n);extraInput[c]=0;ExtraSetup(c);return Plugin_Handled;
}
void ExtraTestMenu(int c){
    if(!Admin(c)||extraKind[c]>1)return;
    Menu m=NewMenu(ExtraTestHandler);m.SetTitle("관리자 본인의 다음 슬롯 1회만 적용\n일반 유저·기본 확률은 변경하지 않음");
    for(int i=0;i<6;i++){char key[8],label[64];IntToString(i+1,key,sizeof(key));Format(label,sizeof(label),"심볼 %d 세 개 일치",i);m.AddItem(key,label);}
    m.AddItem("7","꽝 (보너스 없음)");m.AddItem("0","테스트 취소 / 정상 추첨");m.Display(c,MENU_TIME_FOREVER);
}
public int ExtraTestHandler(Menu m,MenuAction a,int c,int item){
    if(a==MenuAction_End){EndMenu(m);return 0;}if(ending||a!=MenuAction_Select||!Admin(c))return 0;
    char key[8];m.GetItem(item,key,sizeof(key));int value=StringToInt(key);if(value<0||value>7)return 0;
    extraTest[c]=value;PrintToChat(c,"[카지노 테스트] 다음 슬롯 1회 결과 설정: %d (0=정상).",value);ExtraSetup(c);return 0;
}
public bool ExtraInstallTrace(int e,int mask,any c){return e==0||e>MaxClients;}
void ExtraBatch(int c){
    if(!Admin(c)||!ready||seatSlot[c])return;
    int count=extraCount[c],kind=extraKind[c],free;
    for(int g=0;g<GAMES;g++)if(Entity(games[g].body)==-1)free++;
    if(count<1||count>free||GetEntityCount()+count*24>GetMaxEntities()-64){PrintToChat(c,"[카지노] 설치 공간 또는 엔티티 한도가 부족합니다.");return;}
    float eye[3],a[3],hit[3],normal[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,a);
    Handle tr=TR_TraceRayFilterEx(eye,a,MASK_SOLID,RayType_Infinite,ExtraInstallTrace,c);
    bool found=TR_DidHit(tr)&&!TR_StartSolid(tr);TR_GetEndPosition(hit,tr);TR_GetPlaneNormal(tr,normal);delete tr;
    if(!found||normal[2]<0.65||GetVectorDistance(eye,hit)>800.0){PrintToChat(c,"[카지노] 800유닛 이내의 평평한 바닥을 보세요.");return;}
    float positions[GAMES][3],rad=DegToRad(a[1]);
    float mins[3]={-24.0,-24.0,1.0},maxs[3]={24.0,24.0,123.0};
    if(kind>=5){mins[0]=mins[1]=-125.0;maxs[0]=maxs[1]=125.0;maxs[2]=145.0;}
    for(int i=0;i<count;i++){
        float start[3],end[3],offset=(float(i)-float(count-1)*0.5)*extraSpacing[c];start=hit;
        start[0]+=Sine(rad)*offset;start[1]-=Cosine(rad)*offset;start[2]+=50.0;end=start;end[2]-=100.0;
        tr=TR_TraceRayFilterEx(start,end,MASK_SOLID,RayType_EndPoint,ExtraInstallTrace,c);
        found=TR_DidHit(tr)&&!TR_StartSolid(tr);TR_GetEndPosition(positions[i],tr);TR_GetPlaneNormal(tr,normal);delete tr;
        if(!found||normal[2]<0.65||FloatAbs(positions[i][2]-hit[2])>48.0){PrintToChat(c,"[카지노] %d번째 바닥이 없어 설치 취소.",i+1);return;}
        positions[i][2]+=0.1;tr=TR_TraceHullFilterEx(positions[i],positions[i],mins,maxs,MASK_SOLID,ExtraInstallTrace,c);
        bool blocked=TR_DidHit(tr)||TR_StartSolid(tr)||TR_AllSolid(tr);delete tr;
        if(blocked){PrintToChat(c,"[카지노] %d번째 위치가 막혀 설치 취소.",i+1);return;}
    }
    int created[GAMES];
    for(int i=0;i<count;i++){created[i]=CreateGame(c,kind,positions[i],a[1]+180.0);if(created[i]<0){for(int j=0;j<i;j++)Remove(created[j]);PrintToChat(c,"[카지노] 생성 실패: 이번 묶음 설치를 되돌렸습니다.");return;}}
    PrintToChat(c,"[카지노] %d대 설치 / 중심 간격 %.0f",count,extraSpacing[c]);
}
public bool ExtraControlTrace(int e,int mask,any g){
    if(e>0&&e<=MaxClients)return false;
    if(e==Entity(games[g].body)||e==Entity(games[g].stand)||e==Entity(games[g].controls)||e==Entity(machines[g*6].chair))return false;
    for(int i=0;i<3;i++)if(e==Entity(games[g].reel[i]))return false;
    return true;
}
bool ExtraUse(int c){
    if(!Player(c)||!seatSlot[c])return false;
    int g=GameOf(c);if(g<0||games[g].kind>4)return false;
    float eye[3],a[3],dir[3];SeatAim(c,eye,a);GetAngleVectors(a,dir,NULL_VECTOR,NULL_VECTOR);
    for(int b=0;b<(games[g].kind==1?5:4);b++){
        float p[3],delta[3];
        if(b<3&&games[g].kind==1)WorldPoint(g*6,9.635772,5.3609+float(b)*1.92,CABINET_HEIGHT+21.853317,p);
        else if(b<3&&games[g].kind<=1)WorldPoint(g*6,9.741603,4.9001+float(b)*2.3808,CABINET_HEIGHT+21.966666,p);
        else if(b<3)WorldPoint(g*6,8.0888,5.86025+float(b)*1.92,CABINET_HEIGHT+18.7635,p);
        else if(b==4)WorldPoint(g*6,10.19152954,0.00002048,CABINET_HEIGHT+21.50307619,p);
        else WorldPoint(g*6,4.79839,15.0,CABINET_HEIGHT+32.5,p);
        MakeVectorFromPoints(eye,p,delta);float along=GetVectorDotProduct(delta,dir),radius=b<3?(games[g].kind<=1?1.15:0.93):4.0;
        if(b<3&&games[g].kind==1)radius/=1.24;
        if(b==4)radius=2.4;
        if(along<1.0||along>120.0||GetVectorLength(delta,true)-along*along>radius*radius)continue;
        float yaw=DegToRad(games[g].yaw);if((eye[0]-p[0])*Cosine(yaw)+(eye[1]-p[1])*Sine(yaw)<0.0)continue;
        Handle tr=TR_TraceRayFilterEx(eye,p,MASK_SOLID,RayType_EndPoint,ExtraControlTrace,g);bool blocked=TR_DidHit(tr)||TR_StartSolid(tr);delete tr;if(blocked)continue;
        if(rounds[c].phase)return true;
        if(rounds[c].bonus){if(games[g].kind==1&&b>=3)Start(c);return true;}
        if(b<3){if(games[g].kind<=1)SelectBet(c,1+2*b);else{rounds[c].credit=1+2*b;Sound(g,1);}CasinoHint(c,"베팅 %d · 레버를 보고 E/메딕: 시작",rounds[c].credit);}else Start(c);
        return true;
    }
    return false;
}
