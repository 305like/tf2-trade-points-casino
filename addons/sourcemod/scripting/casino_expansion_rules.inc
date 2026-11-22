// Original paytable values; outcome weights and progressive jackpots are local TEST rules.
float WheelProgress(float t){
    // Original WheelCurve keys, also used by wheel_v14 model compilation.
    float times[]={0.0,0.989854813,1.356632233,1.655172348,2.013420105,2.346078873,2.605150223,3.198275805,4.362069130,5.801723957,7.327585220,9.655171394,12.025860786,15.0};
    float values[]={0.0,1.686643600,1.939810991,2.010135174,2.006618977,1.908164978,1.771492004,1.364960909,0.931038618,0.539937496,0.311557412,0.103160501,0.014663219,0.0};
    float area,total;
    for(int i=0;i<13;i++){
        float length=times[i+1]-times[i],d=t-times[i];if(d<0.0)d=0.0;if(d>length)d=length;
        area+=values[i]*d+(values[i+1]-values[i])*d*d/(2.0*length);
        total+=(values[i]+values[i+1])*length*0.5;
    }
    return area/total;
}
int WheelPay(int sector){
    // Clockwise from the top of the original slotwheel_d texture. 23 = free spin.
    int values[24]={200,1000,50,40,30,20,50,700,200,800,450,0,200,400,250,50,10,600,250,350,0,750,500,0};
    return sector>=0&&sector<24?values[sector]:0;
}
int WheelReel(int symbol){
    // Logical paytable order -> Diamond mesh's texture-cell/animation order.
    int cells[6]={0,2,4,1,3,5};
    return symbol>=0&&symbol<6?cells[symbol]:0;
}
void CasinoShuffle(int[] deck,int size){for(int i=0;i<size;i++)deck[i]=i;for(int i=size-1;i>0;i--){int j=GetRandomInt(0,i),v=deck[i];deck[i]=deck[j];deck[j]=v;}}
int VideoPokerPay(const int cards[5],int credit){
    int value=PokerFive(cards),category=value/759375,high=(value%759375)/50625;
    int mult[]={0,2,4,6,8,12,18,50,100};
    if(category==1&&high<11)return 0;
    if(category==8&&high==14)return credit==5?2500:500*credit;
    return mult[category]*credit;
}
int SlotPay(int symbol,int matches,int credit){
    int col=credit==1?0:(credit==3?1:2);
    int triple[6][3]={{100,150,200},{60,100,150},{40,80,120},{30,60,90},{20,40,60},{10,20,30}};
    int one[]={3,5,10},two[]={5,10,15};
    if(matches==3)return triple[symbol][col];
    if(symbol==0&&matches==2)return two[col];
    if(symbol==0&&matches==1)return one[col];
    return 0;
}
bool BingoLine(const int board[25],const bool called[80],bool blackout){
    bool marks[25];for(int i=0;i<25;i++)marks[i]=i==12||called[board[i]];
    if(blackout){for(int i=0;i<25;i++)if(!marks[i])return false;return true;}
    for(int r=0;r<5;r++){bool row=true,col=true;for(int k=0;k<5;k++){row=row&&marks[r*5+k];col=col&&marks[k*5+r];}if(row||col)return true;}
    bool left=true,right=true;for(int i=0;i<5;i++){left=left&&marks[i*6];right=right&&marks[i*5+4-i];}return left||right;
}
int KenoPay(int picks,int hits){
    // shortcut: AGC payout/odds are unpublished; virtual-chip test paytable only.
    int pay[11][11]={{0},{0,2},{0,0,8},{0,0,2,25},{0,0,1,5,80},{0,0,0,2,15,200},{0,0,0,1,5,50,500},{0,0,0,0,2,15,100,1000},{0,0,0,0,1,5,50,500,2000},{0,0,0,0,0,2,20,100,1000,5000},{0,0,0,0,0,1,5,50,500,2000,10000}};
    return picks>=1&&picks<=10&&hits>=0&&hits<=picks?pay[picks][hits]:0;
}
void ExpansionRulesTest(){
    if(FloatAbs(WheelProgress(0.0))>0.0001||FloatAbs(WheelProgress(15.0)-1.0)>0.0001)SetFailState("Wheel audio curve endpoints");
    for(int step=1;step<=900;step++)if(WheelProgress(float(step)/60.0)<WheelProgress(float(step-1)/60.0))SetFailState("Wheel audio curve direction");
    if(WheelPay(1)!=1000||WheelPay(9)!=800||WheelPay(11)!=0||WheelPay(20)!=0||WheelPay(23)!=0||WheelPay(-1)!=0||WheelPay(24)!=0)SetFailState("Wheel sector payout bounds");
    CardRulesTest();int royal[5]={8,9,10,11,12},lowPair[5]={0,13,3,18,33};
    if(VideoPokerPay(royal,5)!=2500||VideoPokerPay(lowPair,1)!=0||SlotPay(0,2,5)!=15||SlotPay(5,3,3)!=20)SetFailState("Expansion payout selftest");
    int board[25];bool called[80];for(int i=0;i<25;i++)board[i]=i;
    if(BingoLine(board,called,false))SetFailState("Empty bingo won");
    for(int i=0;i<5;i++)called[i]=true;
    if(!BingoLine(board,called,false)||BingoLine(board,called,true))SetFailState("Bingo line/blackout selftest");
    for(int i=0;i<25;i++)called[i]=true;if(!BingoLine(board,called,true))SetFailState("Bingo blackout selftest");
    int deck[80];for(int trial=0;trial<50;trial++){CasinoShuffle(deck,80);bool seen[80];for(int i=0;i<80;i++){if(deck[i]<0||deck[i]>=80||seen[deck[i]])SetFailState("Expansion unique draw");seen[deck[i]]=true;}}
    if(KenoPay(10,10)!=10000||KenoPay(0,0)!=0||KenoPay(3,4)!=0)SetFailState("Keno bounds selftest");
}
