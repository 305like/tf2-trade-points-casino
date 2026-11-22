// Pure card rules: card = suit * 13 + rank (0=2, 12=Ace).
int CardRank(int card) { return card % 13 + 2; }
int BlackjackValue(const int[] cards,int count) {
    int total,aces;
    for(int i=0;i<count;i++) {int r=CardRank(cards[i]);if(r==14){aces++;total+=11;}else total+=r>10?10:r;}
    while(total>21&&aces>0){total-=10;aces--;}
    return total;
}
int RankCode(int category,const int ranks[5]) {
    int code=category;
    for(int i=0;i<5;i++)code=code*15+ranks[i];
    return code;
}
int PokerFive(const int cards[5]) {
    int counts[15],sorted[5],keys[5],straight,trip,quad,pairs[2],np;
    bool flush=true;
    for(int i=0;i<5;i++){counts[CardRank(cards[i])]++;if(cards[i]/13!=cards[0]/13)flush=false;}
    int n;
    for(int r=14;r>=2;r--)for(int j=0;j<counts[r];j++)sorted[n++]=r;
    for(int hi=14;hi>=5;hi--){bool ok=true;for(int j=0;j<5;j++){int r=hi-j;if(r==1)r=14;if(!counts[r])ok=false;}if(ok){straight=hi;break;}}
    for(int r=14;r>=2;r--){if(counts[r]==4)quad=r;if(counts[r]==3)trip=r;if(counts[r]==2)pairs[np++]=r;}
    if(flush&&straight){keys[0]=straight;return RankCode(8,keys);}
    if(quad){keys[0]=quad;for(int r=14;r>=2;r--)if(counts[r]==1)keys[1]=r;return RankCode(7,keys);}
    if(trip&&np){keys[0]=trip;keys[1]=pairs[0];return RankCode(6,keys);}
    if(flush)return RankCode(5,sorted);
    if(straight){keys[0]=straight;return RankCode(4,keys);}
    if(trip){keys[0]=trip;n=1;for(int r=14;r>=2;r--)if(counts[r]==1)keys[n++]=r;return RankCode(3,keys);}
    if(np==2){keys[0]=pairs[0];keys[1]=pairs[1];for(int r=14;r>=2;r--)if(counts[r]==1)keys[2]=r;return RankCode(2,keys);}
    if(np==1){keys[0]=pairs[0];n=1;for(int r=14;r>=2;r--)if(counts[r]==1)keys[n++]=r;return RankCode(1,keys);}
    return RankCode(0,sorted);
}
int PokerSeven(const int cards[7]) {
    int best,five[5];
    for(int a=0;a<6;a++)for(int b=a+1;b<7;b++){
        int n;for(int i=0;i<7;i++)if(i!=a&&i!=b)five[n++]=cards[i];
        int value=PokerFive(five);if(value>best)best=value;
    }
    return best;
}
// Side pots include folded contributions, but folded hands cannot win.
// Odd chips go clockwise after the dealer. If everyone departed, refund each contribution.
void SplitPots(const int paid[6],const bool folded[6],const int ranks[6],int dealer,int awards[6]) {
    for(int i=0;i<6;i++)awards[i]=0;
    int previous;
    while(true){
        int level=2147483647;
        for(int i=0;i<6;i++)if(paid[i]>previous&&paid[i]<level)level=paid[i];
        if(level==2147483647)break;
        int pot,best=-1,winners;
        for(int i=0;i<6;i++)if(paid[i]>=level){pot+=level-previous;if(!folded[i]&&ranks[i]>best)best=ranks[i];}
        for(int i=0;i<6;i++)if(paid[i]>=level&&!folded[i]&&ranks[i]==best)winners++;
        if(!winners){for(int i=0;i<6;i++)if(paid[i]>=level)awards[i]+=level-previous;}
        else {
            int extra=pot%winners;
            for(int step=1;step<=6;step++) {int i=(dealer+step)%6;if(paid[i]>=level&&!folded[i]&&ranks[i]==best){awards[i]+=pot/winners;if(extra>0){awards[i]++;extra--;}}}
        }
        previous=level;
    }
}
void PokerReplace(int hole[30],int seat,int mask,const int deck[52],int &cursor,int discard[30],int &discarded){
    int old[5],count;
    for(int j=0;j<5;j++)if(mask&(1<<j)){
        old[count++]=hole[seat*5+j];
        if(cursor<52)hole[seat*5+j]=deck[cursor++];
        else{
            if(discarded<=0)SetFailState("Draw poker discard exhaustion");
            int k=GetRandomInt(0,discarded-1);hole[seat*5+j]=discard[k];discard[k]=discard[--discarded];
        }
    }
    for(int j=0;j<count;j++)discard[discarded++]=old[j];
}
void CardRulesTest() {
    int aces[]={12,25,7};if(BlackjackValue(aces,3)!=21)SetFailState("BJ ace rule");
    int wheel[5]={12,0,1,2,3},six[5]={0,1,2,3,4},quad[5]={0,13,26,39,12};
    if(PokerFive(six)<=PokerFive(wheel)||PokerFive(wheel)<=PokerFive(quad))SetFailState("Poker straight flush rule");
    int full[5]={12,25,38,11,24},flush[5]={0,2,4,6,9};
    if(PokerFive(full)<=PokerFive(flush))SetFailState("Poker full house rule");
    int seven[7]={0,1,2,3,4,25,38};if(PokerSeven(seven)!=PokerFive(six))SetFailState("Poker best seven rule");
    int paid[6]={30,70,70,0,0,0},ranks[6]={300,200,100,0,0,0},awards[6];
    bool folded[6]={false,false,false,true,true,true};SplitPots(paid,folded,ranks,0,awards);
    if(awards[0]!=90||awards[1]!=80||awards[2]!=0)SetFailState("Poker side pot rule");
    paid[0]=paid[1]=paid[2]=5;ranks[0]=ranks[1]=200;folded[2]=true;SplitPots(paid,folded,ranks,0,awards);
    if(awards[0]!=7||awards[1]!=8)SetFailState("Poker tie odd chip rule");
    for(int trial=0;trial<100;trial++){
        int deck[52],hole[30],discard[30],cursor=30,discarded;
        for(int i=0;i<52;i++)deck[i]=i;
        for(int i=0;i<30;i++)hole[i]=i;
        for(int i=0;i<6;i++){
            int old[5];for(int j=0;j<5;j++)old[j]=hole[i*5+j];
            PokerReplace(hole,i,31,deck,cursor,discard,discarded);
            bool seen[52];for(int j=0;j<30;j++){if(hole[j]<0||hole[j]>=52||seen[hole[j]])SetFailState("Draw poker duplicate hand");seen[hole[j]]=true;}
            for(int j=0;j<5;j++)for(int k=0;k<5;k++)if(old[j]==hole[i*5+k])SetFailState("Draw poker returned own discard");
        }
        if(cursor!=52||discarded!=22)SetFailState("Draw poker deck conservation");
    }
    for(int trial=0;trial<100;trial++){
        int invested,returned;
        for(int i=0;i<6;i++){paid[i]=GetRandomInt(0,100);ranks[i]=GetRandomInt(1,3);folded[i]=GetRandomInt(0,1)==1;invested+=paid[i];}
        SplitPots(paid,folded,ranks,trial%6,awards);
        for(int i=0;i<6;i++){if(awards[i]<0)SetFailState("Negative award");returned+=awards[i];}
        if(invested!=returned)SetFailState("Pot conservation");
    }
}
