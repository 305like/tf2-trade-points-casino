#include <sdkhooks>
#include <tf2_stocks>
#define TICKET_PARTS 140
#define TILES 112
#define PIXELS 448
char ticketModels[][]={"board","number","grade","tileluck_quarter","tilecell_quarter","cursor"};
bool active[MAXPLAYERS+1],revealed[MAXPLAYERS+1],scratched[MAXPLAYERS+1][PIXELS];
int parts[MAXPLAYERS+1][TICKET_PARTS],partCount[MAXPLAYERS+1],tileRef[MAXPLAYERS+1][TILES],cursorRef[MAXPLAYERS+1];
int owner[2049],resultRank[MAXPLAYERS+1];
int winningPanel[MAXPLAYERS+1],panelDone[MAXPLAYERS+1][7];
bool pointing[MAXPLAYERS+1];
float eye[MAXPLAYERS+1][3],view[MAXPLAYERS+1][3];
float pointerX[MAXPLAYERS+1],pointerY[MAXPLAYERS+1],expires[MAXPLAYERS+1];
float tileX[TILES],tileY[TILES],pixelX[PIXELS],pixelY[PIXELS];
bool assetsReady;
void InitTicket(){
 int counts[7];counts[2]=47;if(ReadyToReveal(2,counts))SetFailState("Early reveal at 47/64");
 counts[1]=64;if(ReadyToReveal(2,counts))SetFailState("Nonwinning panel revealed winner");
 counts[2]=48;if(!ReadyToReveal(2,counts))SetFailState("Missing reveal at 48/64");
 if(!ReadyToReveal(-1,counts))SetFailState("Loss reveal failed");
 for(int i=0;i<7;i++)counts[i]=0;counts[0]=64;if(ReadyToReveal(-1,counts))SetFailState("Lucky panel caused loss reveal");
 float testEye[3],testRay[3]={1.0,0.0,0.0},px,py;
 if(!ProjectTicket(testEye,testRay,px,py)||FloatAbs(px-32.0)>0.001||FloatAbs(py-20.0)>0.001)SetFailState("Center projection failed");
 testEye[1]=10.0;testEye[2]=5.0;
 if(!ProjectTicket(testEye,testRay,px,py)||FloatAbs(px-22.0)>0.001||FloatAbs(py-15.0)>0.001)SetFailState("Moved projection failed");
 testRay[0]=-1.0;if(ProjectTicket(testEye,testRay,px,py))SetFailState("Behind projection failed");
 testRay[0]=0.0;if(ProjectTicket(testEye,testRay,px,py))SetFailState("Parallel projection failed");
 testRay[0]=1.0;testEye[1]=100.0;if(ProjectTicket(testEye,testRay,px,py))SetFailState("Outside projection failed");
 testEye[1]=0.0;testEye[0]=-200.0;if(ProjectTicket(testEye,testRay,px,py))SetFailState("Distance projection failed");
 for(int panel=0;panel<7;panel++){
  float x=panel==0?5.50:22.65+float((panel-1)%3)*12.30;
  float y=panel==0?15.20:15.20+float((panel-1)/3)*8.40;
  float w=panel==0?3.68:2.90,h=panel==0?4.06:1.92;
  for(int j=0;j<16;j++){
   int i=panel*16+j;tileX[i]=x+(float(j%4)+0.5)*w;tileY[i]=y+(float(j/4)+0.5)*h;
   for(int q=0;q<4;q++){pixelX[i*4+q]=tileX[i]+(q%2==0?-w/4.0:w/4.0);pixelY[i*4+q]=tileY[i]+(q/2==0?-h/4.0:h/4.0);}
  }
 }
 for(int r=0;r<6;r++)for(int test=0;test<100;test++){
  int lucky=GetRandomInt(1,30),nums[6],grades[6],hits;Combination(r,lucky,nums,grades);
  for(int i=0;i<6;i++){
   if(nums[i]<1||nums[i]>30||grades[i]<1||grades[i]>5)SetFailState("Invalid ticket values");
   if(nums[i]==lucky){hits++;if(grades[i]!=r)SetFailState("Ticket rank mismatch");}
   for(int j=0;j<i;j++)if(nums[j]==nums[i])SetFailState("Duplicate ticket number");
  }
  if(hits!=(r>0?1:0))SetFailState("Ticket outcome mismatch");
 }
}
void Combination(int rank,int lucky,int nums[6],int grades[6]){
 for(int i=0;i<6;i++){
  bool unique;do{nums[i]=GetRandomInt(1,30);unique=nums[i]!=lucky;for(int j=0;j<i;j++)if(nums[j]==nums[i])unique=false;}while(!unique);
  grades[i]=GetRandomInt(1,5);
 }
 if(rank>0){int match=GetRandomInt(0,5);nums[match]=lucky;grades[match]=rank;}
}
void CacheTickets(){
 assetsReady=true;char path[PLATFORM_MAX_PATH];BuildPath(Path_SM,path,sizeof(path),"configs/scratch_lottery_downloads.txt");File f=OpenFile(path,"r");
 if(f==null){assetsReady=false;return;}
 while(f.ReadLine(path,sizeof(path))){TrimString(path);if(path[0]){if(!FileExists(path,true))assetsReady=false;else AddFileToDownloadsTable(path);}}delete f;
 for(int i=0;i<sizeof(ticketModels);i++){Format(path,sizeof(path),"models/suspicious_ticket_v1/%s.mdl",ticketModels[i]);if(!FileExists(path,true)||PrecacheModel(path,true)==0)assetsReady=false;}
}
int Ref(int ref){int e=EntRefToEntIndex(ref);return e>MaxClients&&IsValidEntity(e)?e:-1;}
public Action TicketTransmit(int e,int c){return owner[e]==c?Plugin_Continue:Plugin_Handled;}
void TicketPoint(int c,float x,float y,float depth,float p[3]){
 float yaw=DegToRad(view[c][1]);p[0]=eye[c][0]+Cosine(yaw)*depth-Sine(yaw)*(32.0-x);p[1]=eye[c][1]+Sine(yaw)*depth+Cosine(yaw)*(32.0-x);p[2]=eye[c][2]+20.0-y;
}
int Part(int c,int model,float x,float y,float depth,int skin=0){
 if(partCount[c]>=TICKET_PARTS)return -1;int e=CreateEntityByName("prop_dynamic_override");if(e<0||e>=sizeof(owner)){if(e>0)RemoveEntity(e);return -1;}
 char path[128];Format(path,sizeof(path),"models/suspicious_ticket_v1/%s.mdl",ticketModels[model]);DispatchKeyValue(e,"model",path);DispatchKeyValue(e,"solid","0");
 if(!DispatchSpawn(e)){RemoveEntity(e);return -1;}
 SetEntProp(e,Prop_Send,"m_nSkin",skin);SetEntProp(e,Prop_Data,"m_takedamage",0);owner[e]=c;SDKHook(e,SDKHook_SetTransmit,TicketTransmit);
 float p[3];TicketPoint(c,x,y,depth,p);TeleportEntity(e,p,view[c],NULL_VECTOR);parts[c][partCount[c]++]=EntIndexToEntRef(e);return e;
}
void CloseTicket(int c){
 active[c]=false;pointing[c]=false;
 for(int i=0;i<partCount[c];i++){int e=Ref(parts[c][i]);if(e!=-1){owner[e]=0;RemoveEntity(e);}}partCount[c]=0;
}
public void TicketDeath(Event event,const char[] name,bool dontBroadcast){int c=GetClientOfUserId(event.GetInt("userid"));if(c)CloseTicket(c);}
public Action TicketDamage(int c,int &attacker,int &inflictor,float &damage,int &type){if(active[c]&&damage>0.0)CloseTicket(c);return Plugin_Continue;}
void StartTicket(int c){
 if(active[c]||!Player(c))return;
 int count;for(int i=1;i<=MaxClients;i++)if(active[i])count++;
 // shortcut: four simultaneous tickets until real-client entity/bandwidth profiling is complete.
 if(!assetsReady||count>=4||GetEntityCount()>GetMaxEntities()-200){PrintToChat(c,"[복권] 잠시 후 다시 이용하세요. 리소스 또는 표시 공간이 부족합니다.");return;}
 int camera=GetEntPropEnt(c,Prop_Data,"m_hViewEntity");
 if(GetEntityMoveType(c)!=MOVETYPE_WALK||!(GetEntityFlags(c)&FL_ONGROUND)||(GetEntityFlags(c)&FL_DUCKING)||TF2_IsPlayerInCondition(c,TFCond_Taunting)||(camera>0&&camera!=c)){PrintToChat(c,"[복권] 지상에서 서 있는 상태로 이용하세요. 다른 탑승/도발 중에는 이용할 수 없습니다.");return;}
 GetClientEyePosition(c,eye[c]);GetClientEyeAngles(c,view[c]);view[c][0]=view[c][2]=0.0;
 active[c]=true;revealed[c]=false;pointing[c]=false;pointerX[c]=32.0;pointerY[c]=20.0;expires[c]=GetGameTime()+120.0;
 winningPanel[c]=-1;for(int i=0;i<7;i++)panelDone[c][i]=0;for(int i=0;i<PIXELS;i++)scratched[c][i]=false;
 int rank=Rank(GetRandomInt(0,99)),lucky=GetRandomInt(1,30);resultRank[c]=rank;
 int nums[6],grades[6];
 Combination(rank,lucky,nums,grades);
 for(int i=0;i<6;i++)if(nums[i]==lucky)winningPanel[c]=i+1;
 bool ok=Part(c,0,32.0,20.0,50.0)!=-1;
 if(Part(c,1,12.85,23.3,49.9,lucky-1)==-1)ok=false;
 for(int i=0;i<6;i++){
  float x=28.45+float(i%3)*12.30,y=18.20+float(i/3)*8.40;
  if(Part(c,1,x,y,49.9,nums[i]-1)==-1)ok=false;
  if(Part(c,2,x,21.5+float(i/3)*8.40,49.9,grades[i]-1)==-1)ok=false;
 }
 for(int i=0;i<TILES;i++){int e=Part(c,i<16?3:4,tileX[i],tileY[i],49.8);tileRef[c][i]=e==-1?INVALID_ENT_REFERENCE:EntIndexToEntRef(e);if(e==-1)ok=false;}
 int e=Part(c,5,32.0,20.0,49.6);cursorRef[c]=e==-1?INVALID_ENT_REFERENCE:EntIndexToEntRef(e);if(e==-1)ok=false;
 if(!ok){CloseTicket(c);PrintToChat(c,"[복권] 화면 생성 실패. 다시 시도하세요.");return;}
 PrintToChat(c,"[수상한복권] 이동/시점 자유. 당첨 칸 75%%를 긁으면 전체 공개 / R: 닫기");
}
bool ProjectTicket(float localEye[3],float localDir[3],float &x,float &y){
 if(localDir[0]<=0.001)return false;
 float t=(49.8-localEye[0])/localDir[0];if(t<0.0||t>150.0)return false;
 x=32.0-(localEye[1]+localDir[1]*t);y=20.0-(localEye[2]+localDir[2]*t);
 return x>=0.0&&x<=64.0&&y>=0.0&&y<=40.0;
}
void ScratchMove(int c,const float angles[3]){
 float p0[3],dir[3],local[3],ray[3];GetClientEyePosition(c,p0);GetAngleVectors(angles,dir,NULL_VECTOR,NULL_VECTOR);
 float co=Cosine(DegToRad(view[c][1])),si=Sine(DegToRad(view[c][1]));
 float dx0=p0[0]-eye[c][0],dy0=p0[1]-eye[c][1];local[0]=dx0*co+dy0*si;local[1]=-dx0*si+dy0*co;local[2]=p0[2]-eye[c][2];
 ray[0]=dir[0]*co+dir[1]*si;ray[1]=-dir[0]*si+dir[1]*co;ray[2]=dir[2];
 float nx,ny;int cursor=Ref(cursorRef[c]);
 if(!ProjectTicket(local,ray,nx,ny)){pointing[c]=false;if(cursor!=-1)SetEntProp(cursor,Prop_Send,"m_fEffects",GetEntProp(cursor,Prop_Send,"m_fEffects")|32);return;}
 if(cursor!=-1)SetEntProp(cursor,Prop_Send,"m_fEffects",GetEntProp(cursor,Prop_Send,"m_fEffects")&~32);
 float ox=pointing[c]?pointerX[c]:nx,oy=pointing[c]?pointerY[c]:ny;pointing[c]=true;pointerX[c]=nx;pointerY[c]=ny;
 float p[3];int e=Ref(cursorRef[c]);if(e!=-1){TicketPoint(c,pointerX[c],pointerY[c],49.6,p);TeleportEntity(e,p,NULL_VECTOR,NULL_VECTOR);}
 if(revealed[c]||(FloatAbs(nx-ox)<0.001&&FloatAbs(ny-oy)<0.001))return;
 float dx=pointerX[c]-ox,dy=pointerY[c]-oy,len=dx*dx+dy*dy;
 for(int i=0;i<PIXELS;i++){
  if(scratched[c][i])continue;float t=len>0.0?((pixelX[i]-ox)*dx+(pixelY[i]-oy)*dy)/len:0.0;t=FloatMax(0.0,FloatMin(1.0,t));
  float x=ox+t*dx-pixelX[i],y=oy+t*dy-pixelY[i];if(x*x+y*y>1.0)continue;
  scratched[c][i]=true;panelDone[c][i/64]++;e=Ref(tileRef[c][i/4]);if(e!=-1)SetEntProp(e,Prop_Send,"m_nBody",GetEntProp(e,Prop_Send,"m_nBody")|(1<<(i%4)));
 }
 if(ReadyToReveal(winningPanel[c],panelDone[c])){
  revealed[c]=true;for(int i=0;i<TILES;i++){e=Ref(tileRef[c][i]);if(e!=-1)SetEntProp(e,Prop_Send,"m_fEffects",GetEntProp(e,Prop_Send,"m_fEffects")|32);}
  if(resultRank[c])PrintToChat(c,"[수상한복권] %d등 당첨! R키로 닫으세요. (테스트: 지급 없음)",resultRank[c]);else PrintToChat(c,"[수상한복권] 꽝! R키로 닫으세요.");
 }
}
bool ReadyToReveal(int win,const int counts[7]){
 if(win>0)return counts[win]>=48;
 for(int i=1;i<7;i++)if(counts[i]>=48)return true;
 return false;
}
float FloatMin(float a,float b){return a<b?a:b;}
float FloatMax(float a,float b){return a>b?a:b;}
