// World-space presentation. Hidden cards never transmit their face to opponents.
#define VIEW_CARDS 144
#define VIEW_ENTITIES 4096
enum struct CardView {
    int face;
    int back;
    int card;
    int audience; // -1 public, 0 nobody, otherwise Steam session userid.
    bool wanted;
    bool moving;
    bool collecting;
    bool sounded;
    float start;
    float from[3];
    float target[3];
    float yaw;
}
CardView cardView[TABLES][VIEW_CARDS];
int viewTable[VIEW_ENTITIES],viewSlot[VIEW_ENTITIES];
bool viewFace[VIEW_ENTITIES];
int viewText[TABLES][7],viewChip[TABLES][24],viewButton[TABLES];
float viewHold[TABLES],viewBJHold[MAXPLAYERS+1],viewBusy[TABLES];
float viewNextHand[TABLES];
char viewLog[TABLES][192];
char cardModels[][]={"models/tower_cards_v2/card0.mdl","models/tower_cards_v2/card1.mdl","models/tower_cards_v2/card2.mdl","models/tower_cards_v2/card3.mdl"};

bool ViewPrecache(){
    for(int i=0;i<4;i++)if(!FileExists(cardModels[i],true)||!PrecacheModel(cardModels[i],true))return false;
    return PrecacheModel("models/tower_cards_v2/chip.mdl",true)>0&&PrecacheModel("models/tower_cards_v2/button.mdl",true)>0;
}
float ViewHeight(int t){return tables[t].kind==0?50.8:49.0;}
void ViewPosition(int t,float x,float y,float p[3]){p=tables[t].origin;p[0]+=x;p[1]+=y;p[2]+=ViewHeight(t);}
void ViewSeatPosition(int t,int seat,float inset,float side,float p[3]){
    float rad=DegToRad(machines[t*6+seat].yaw);
    // Table models are installed at yaw -90: short dimension is world X.
    ViewPosition(t,Cosine(rad)*(tables[t].kind==0?32.0:35.0)*inset-Sine(rad)*side,
        Sine(rad)*(tables[t].kind==0?65.0:82.0)*inset+Cosine(rad)*side,p);
}
void ViewKill(int ref){int e=Entity(ref);if(e!=-1)RemoveEntity(e);}
void ViewClear(int t){
    for(int k=0;k<VIEW_CARDS;k++){
        ViewKill(cardView[t][k].face);ViewKill(cardView[t][k].back);
        CardView blank;cardView[t][k]=blank;
    }
    for(int i=0;i<7;i++){ViewKill(viewText[t][i]);viewText[t][i]=0;}
    for(int i=0;i<24;i++){ViewKill(viewChip[t][i]);viewChip[t][i]=0;}
    ViewKill(viewButton[t]);viewButton[t]=0;viewHold[t]=viewBusy[t]=viewNextHand[t]=0.0;viewLog[t][0]=0;
}
bool ViewFaceAllowed(int audience,int viewer,float elapsed,bool collecting){
    return !collecting&&elapsed>=0.20&&(audience==-1||(audience>0&&audience==viewer));
}
public Action ViewTransmit(int e,int client){
    if(e<=MaxClients||e>=VIEW_ENTITIES)return Plugin_Handled;
    int t=viewTable[e],k=viewSlot[e];
    if(t<0||t>=TABLES||k<0||k>=VIEW_CARDS)return Plugin_Handled;
    bool face=viewFace[e];
    if(Entity(face?cardView[t][k].face:cardView[t][k].back)!=e)return Plugin_Handled;
    if(!cardView[t][k].wanted&&!cardView[t][k].collecting)return Plugin_Handled;
    float elapsed=GetGameTime()-cardView[t][k].start;
    if(elapsed<0.0)return Plugin_Handled;
    bool visible=ViewFaceAllowed(cardView[t][k].audience,GetClientUserId(client),elapsed,cardView[t][k].collecting);
    return face==visible?Plugin_Continue:Plugin_Handled;
}
int ViewCardEntity(int t,int k,bool face){
    if(GetEntityCount()>=GetMaxEntities()-128)return INVALID_ENT_REFERENCE;
    int ref=Prop(cardModels[0]),e=Entity(ref);if(e==-1)return ref;
    if(e>=VIEW_ENTITIES){RemoveEntity(e);return INVALID_ENT_REFERENCE;}
    viewTable[e]=t;viewSlot[e]=k;viewFace[e]=face;
    SetEntProp(e,Prop_Send,"m_nSkin",13);
    SetEntProp(e,Prop_Send,"m_fEffects",GetEntProp(e,Prop_Send,"m_fEffects")|16);
    SDKHook(e,SDKHook_SetTransmit,ViewTransmit);
    return ref;
}
void ViewPut(int t,int k,int card,int audience,const float p[3],float yaw,float delay=0.0){
    if(k<0||k>=VIEW_CARDS||card<0||card>=52)return;
    bool fresh=!cardView[t][k].wanted||cardView[t][k].card!=card;
    if(Entity(cardView[t][k].face)==-1)cardView[t][k].face=ViewCardEntity(t,k,true);
    if(Entity(cardView[t][k].back)==-1)cardView[t][k].back=ViewCardEntity(t,k,false);
    int face=Entity(cardView[t][k].face),back=Entity(cardView[t][k].back);
    if(face==-1||back==-1)return;
    SetEntityModel(face,cardModels[card/13]);SetEntProp(face,Prop_Send,"m_nSkin",card%13);
    bool flip=cardView[t][k].audience!=audience;
    cardView[t][k].card=card;cardView[t][k].audience=audience;
    cardView[t][k].wanted=true;cardView[t][k].collecting=false;
    // Compiled card model axes are rotated 90 degrees from the layout axes.
    cardView[t][k].target=p;cardView[t][k].yaw=yaw+90.0;
    if(fresh||flip){
        cardView[t][k].start=GetGameTime()+delay;cardView[t][k].moving=true;cardView[t][k].sounded=false;
        if(fresh)ViewPosition(t,0.0,-12.0,cardView[t][k].from);else cardView[t][k].from=p;
        if(cardView[t][k].start+0.45>viewBusy[t])viewBusy[t]=cardView[t][k].start+0.45;
    }
}
void ViewCollect(int t,int from,int to){
    for(int k=from;k<to;k++)if(cardView[t][k].wanted){
        cardView[t][k].wanted=false;cardView[t][k].collecting=true;cardView[t][k].moving=true;
        cardView[t][k].from=cardView[t][k].target;ViewPosition(t,0.0,-12.0,cardView[t][k].target);
        cardView[t][k].start=GetGameTime();cardView[t][k].sounded=true;
    }
}
void ViewLabel(int t,int slot,const char[] message,const float p[3]){
    int e=Entity(viewText[t][slot]);
    if(e==-1){
        if(GetEntityCount()>=GetMaxEntities()-128)return;
        e=CreateEntityByName("point_worldtext");if(e==-1)return;
        DispatchKeyValue(e,"textsize","2.5");DispatchKeyValue(e,"orientation","1");
        DispatchKeyValue(e,"color","255 230 160 255");
        DispatchKeyValue(e,"message",message);
        if(!DispatchSpawn(e)){RemoveEntity(e);return;}
        viewText[t][slot]=EntIndexToEntRef(e);
    }else {SetVariantString(message);AcceptEntityInput(e,"SetText");}
    float at[3];at=p;at[2]+=7.0;TeleportEntity(e,at,NULL_VECTOR,NULL_VECTOR);
}
void ViewChips(int t,int slot,int value,const float p[3]){
    // Four visible chips per pile; the label always displays the exact value.
    int count=value<=0?0:(value<40?1:(value<100?2:(value<500?3:4)));
    for(int j=0;j<4;j++){
        int idx=slot*4+j,e=Entity(viewChip[t][idx]);
        if(j<count&&e==-1&&GetEntityCount()<GetMaxEntities()-128){viewChip[t][idx]=Prop("models/tower_cards_v2/chip.mdl");e=Entity(viewChip[t][idx]);}
        if(e==-1)continue;
        SetEntityRenderMode(e,RENDER_TRANSCOLOR);SetEntityRenderColor(e,255,255,255,j<count?255:0);
        float at[3];at=p;at[2]+=float(j)*0.75;TeleportEntity(e,at,NULL_VECTOR,NULL_VECTOR);
    }
}
void ViewPoker(int t,bool showdown=false){
    float p[3];int pot;
    for(int i=0;i<6;i++){
        pot+=tables[t].paid[i];int c=Owner(t,i);
        if(tables[t].users[i]&&!tables[t].folded[i]){
            int count=tables[t].kind==2?5:2;
            for(int j=0;j<count;j++){
                ViewSeatPosition(t,i,0.87,(float(j)-float(count-1)*0.5)*6.0,p);
                ViewPut(t,i*5+j,tables[t].hole[i*5+j],showdown?-1:tables[t].users[i],p,machines[t*6+i].yaw-90.0,float(i*2+j)*0.06);
            }
        }else ViewCollect(t,i*5,i*5+5);
        ViewSeatPosition(t,i,0.58,0.0,p);ViewChips(t,i,tables[t].paid[i],p);
        char label[192];
        Format(label,sizeof(label),"%sSEAT %d\nBET %d / BANK %d%s",tables[t].phase&&tables[t].actor==i?"> ":"",i+1,tables[t].paid[i],c?chips[c]:0,tables[t].users[i]&&tables[t].folded[i]?" FOLD":"");
        ViewLabel(t,i,label,p);
    }
    for(int j=0;j<tables[t].shown;j++){
        ViewPosition(t,(float(j)-2.0)*8.0,0.0,p);ViewPut(t,30+j,tables[t].board[j],-1,p,0.0,float(j)*0.12);
    }
    ViewPosition(t,0.0,17.0,p);char status[256];Format(status,sizeof(status),"POT %d / %s\n%s",pot,showdown?"SHOWDOWN":(tables[t].kind==2?"5 CARD DRAW":"TEXAS HOLD'EM"),viewLog[t]);ViewLabel(t,6,status,p);
    if(Entity(viewButton[t])==-1&&GetEntityCount()<GetMaxEntities()-128)viewButton[t]=Prop("models/tower_cards_v2/button.mdl");
    int button=Entity(viewButton[t]);if(button!=-1){ViewSeatPosition(t,tables[t].dealer,0.72,12.0,p);TeleportEntity(button,p,NULL_VECTOR,NULL_VECTOR);}
}
void ViewBJ(int c,bool reveal=false){
    if(!seatSlot[c])return;int s=seatSlot[c]-1,t=s/6,i=s%6;float p[3];
    for(int j=0;j<blackjack[c].count;j++){
        ViewSeatPosition(t,i,0.88,float(j)*2.8-4.0,p);p[2]+=float(j)*0.1;
        ViewPut(t,i*24+j,blackjack[c].hand[j],-1,p,machines[s].yaw-90.0,float(j)*0.12);
    }
    for(int j=0;j<blackjack[c].dc;j++){
        ViewSeatPosition(t,i,0.45,float(j)*2.8-4.0,p);p[2]+=float(j)*0.1;
        ViewPut(t,i*24+12+j,blackjack[c].dealer[j],reveal||j==0?-1:0,p,machines[s].yaw+90.0,float(j)*0.2);
    }
    ViewSeatPosition(t,i,0.67,9.0,p);ViewChips(t,i,blackjack[c].wager,p);
    char label[128];
    Format(label,sizeof(label),"SEAT %d / SCORE %d\nBET %d%s",i+1,BlackjackValue(blackjack[c].hand,blackjack[c].count),blackjack[c].wager,reveal?" RESULT":"");ViewLabel(t,i,label,p);
    ViewPosition(t,0.0,0.0,p);ViewLabel(t,6,"BLACKJACK\nS17 / 3:2",p);
}
void ViewAction(int t,int c,const char[] action){
    Format(viewLog[t],sizeof(viewLog[]),"SEAT %d: %s",(seatSlot[c]-1)%6+1,action);
    for(int i=0;i<6;i++){int viewer=Seated(t*6+i);if(viewer)PrintToChat(viewer,"[테이블] %N: %s",c,action);}
}
void ViewFrame(float now){
    for(int t=0;t<TABLES;t++){
        if(Entity(tables[t].body)==-1)continue;
        for(int k=0;k<VIEW_CARDS;k++)if(cardView[t][k].moving){
            float f=(now-cardView[t][k].start)/0.4;if(f<0.0)continue;if(f>1.0)f=1.0;
            float ease=f*f*(3.0-2.0*f),p[3],angle[3];angle[1]=cardView[t][k].yaw;
            for(int axis=0;axis<3;axis++)p[axis]=cardView[t][k].from[axis]+(cardView[t][k].target[axis]-cardView[t][k].from[axis])*ease;
            p[2]+=Sine(f*FLOAT_PI)*2.0;
            angle[2]=cardView[t][k].collecting?0.0:(f<0.5?f*180.0:(1.0-f)*180.0);
            int face=Entity(cardView[t][k].face),back=Entity(cardView[t][k].back);
            if(face!=-1)TeleportEntity(face,p,angle,NULL_VECTOR);if(back!=-1)TeleportEntity(back,p,angle,NULL_VECTOR);
            if(!cardView[t][k].sounded&&f>=0.5){cardView[t][k].sounded=true;SoundAt(t,0);}
            if(f>=1.0){cardView[t][k].moving=false;cardView[t][k].collecting=false;}
        }
        if(viewHold[t]>0.0&&now>=viewHold[t]){
            viewHold[t]=0.0;ViewCollect(t,0,35);viewBusy[t]=now+0.6;viewNextHand[t]=now+0.7;
            SoundAt(t,10);
        }
        if(viewNextHand[t]>0.0&&now>=viewNextHand[t]){viewNextHand[t]=0.0;StartPoker(t);}
    }
    for(int c=1;c<=MaxClients;c++)if(viewBJHold[c]>0.0&&now>=viewBJHold[c]){
        viewBJHold[c]=0.0;
        if(seatSlot[c]){int s=seatSlot[c]-1;ViewCollect(s/6,(s%6)*24,(s%6+1)*24);ShowGame(c);}
    }
}
public Action ViewSelfTest(int c,int args){
    if(!ready){ReplyToCommand(c,"FAIL assets not ready");return Plugin_Handled;}
    int t=-1;for(int i=0;i<TABLES;i++)if(Entity(tables[i].body)==-1){t=i;break;}
    if(t==-1){ReplyToCommand(c,"SKIP no free test slot");return Plugin_Handled;}
    ViewClear(t);float p[3];p[2]=-10000.0;
    bool ok=true;
    for(int card=0;card<52;card++){
        ViewPut(t,0,card,123,p,0.0);
        int e=Entity(cardView[t][0].face);
        if(e==-1||GetEntProp(e,Prop_Send,"m_nSkin")!=card%13){ok=false;break;}
    }
    ViewLabel(t,0,"CARD TEST",p);int label=Entity(viewText[t][0]);
    if(label==-1)ok=false;else{SetVariantString("UPDATED");if(!AcceptEntityInput(label,"SetText"))ok=false;}
    ViewChips(t,0,500,p);for(int i=0;i<4;i++)if(Entity(viewChip[t][i])==-1)ok=false;
    ViewClear(t);
    ReplyToCommand(c,"CasinoCards visual %s: 52 skin selections, face/back props, worldtext input, 4 chips, cleanup",ok?"PASS":"FAIL");
    return Plugin_Handled;
}
