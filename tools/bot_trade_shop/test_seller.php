<?php
declare(strict_types=1);
require __DIR__.'/catalog.php';require __DIR__.'/seller.php';
function check(bool $v): void {if(!$v)throw new RuntimeException('test failed');}
check(sellerPriceText(['keys'=>0,'refined'=>'3'])==='3정');
check(sellerPriceText(['keys'=>'0','refined'=>'1.55'])==='1.55정');
check(sellerPriceText(['keys'=>2,'refined'=>'3'])==='2키 + 3정');
foreach(['1.11'=>[10,1,0,1,'1.11'],'1.55'=>[14,1,1,2,'1.55'],'1.88'=>[17,1,2,2,'1.88'],'1.99'=>[18,2,0,0,'2'],'0.99'=>[9,1,0,0,'1'],'2'=>[18,2,0,0,'2']] as $input=>$expected){
    $p=sellerPrice(['keys'=>'0','refined'=>(string)$input]);
    check([$p['metal_scrap'],$p['whole'],$p['reclaimed'],$p['scrap'],$p['refined']]===$expected);
}
for($whole=0;$whole<100;$whole++)for($fraction=0;$fraction<=9;$fraction++){
    $p=sellerPrice(['keys'=>'1','refined'=>$whole.'.'.str_pad((string)($fraction*11),2,'0',STR_PAD_LEFT)]);
    check($p['metal_scrap']===$whole*9+$fraction);
    check(sellerPrice(['keys'=>'1','refined'=>$p['refined']])['metal_scrap']===$p['metal_scrap']);
}
foreach(['-1','1.12','1.1','1.999','1e2','NaN','1,11','01.11','999999.99'] as $bad){
    try{sellerPrice(['keys'=>'0','refined'=>$bad]);throw new RuntimeException('bad metal accepted');}catch(InvalidArgumentException $expected){}
}
foreach(['-1','1.1','1e2'] as $bad){
    try{sellerPrice(['keys'=>$bad,'refined'=>'1']);throw new RuntimeException('bad key accepted');}catch(InvalidArgumentException $expected){}
}
try{sellerPrice(['keys'=>'0','refined'=>'0']);throw new RuntimeException('zero accepted');}catch(InvalidArgumentException $expected){}
$index=itemIndex();check(count($index)>1000);
$ko=searchItems($index,'보급 상자 열쇠');$en=searchItems($index,'Mann Co. Supply Crate Key');
check(selectedItem($ko,'5021')['en']===selectedItem($en,'5021')['en']);
check(searchItems($index,'nonexistent-product-zzzyyy')===[]);
foreach(['병과토큰 - 스나이퍼','병과 토큰 스나이퍼','Class Token-Sniper','스나이퍼'] as $q)check(selectedItem(searchItems($index,$q),'5004')['en']==='Class Token - Sniper');
try{selectedItem($en,'999999999');throw new RuntimeException('forged item accepted');}catch(InvalidArgumentException $expected){}
echo "PASS integer scrap normalization (1000 round-trips), boundaries, invalid decimals, Korean/English lookup, forged selections\n";
