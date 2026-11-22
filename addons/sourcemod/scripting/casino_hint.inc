float casinoHintUntil[MAXPLAYERS+1];
int casinoHintSerial[MAXPLAYERS+1];
void CasinoHint(int c,const char[] format,any ...){
 if(c<1||c>MaxClients||!IsClientInGame(c))return;
 char text[512];VFormat(text,sizeof(text),format,3);PrintHintText(c,"%s",text);
 casinoHintUntil[c]=GetGameTime()+5.0;casinoHintSerial[c]=GetClientSerial(c);
}
void CasinoHintReset(){for(int c=1;c<=MaxClients;c++)casinoHintUntil[c]=0.0;}
void CasinoHintFrame(){
 float now=GetGameTime();
 for(int c=1;c<=MaxClients;c++)if(casinoHintUntil[c]>0.0&&now>=casinoHintUntil[c]){
  casinoHintUntil[c]=0.0;if(IsClientInGame(c)&&GetClientSerial(c)==casinoHintSerial[c])PrintHintText(c," ");
 }
}
