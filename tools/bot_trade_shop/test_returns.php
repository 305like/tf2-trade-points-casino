<?php
require __DIR__.'/settings.php';require __DIR__.'/listings.php';require __DIR__.'/checkout.php';require __DIR__.'/returns.php';
function check($ok){if(!$ok)throw new RuntimeException('Assertion failed');}
function rejects($fn){try{$fn();}catch(InvalidArgumentException $e){return;}throw new RuntimeException('Expected rejection');}
$dir=sys_get_temp_dir().'/return-'.bin2hex(random_bytes(6));mkdir($dir);mkdir($dir.'/users');
$owner='76561199077147589';$buyer='76561198038759714';$listing=str_repeat('a',32);
foreach([$owner,$buyer] as $sid)saveTradeURL($dir,$sid,'https://steamcommunity.com/tradeoffer/new/?partner='.((int)$sid-76561197960265728).'&token=Abc_123-');
listingWrite($dir,static function(&$rows)use($owner,$listing){$rows[$listing]=['status'=>'published','owner'=>$owner,'bot_asset'=>'500','price'=>['keys'=>0,'metal_scrap'=>9]];});
rejects(fn()=>returnCreate($dir,$listing,$owner));file_put_contents($dir.'/users/return-heartbeat',time());file_put_contents($dir.'/users/checkout-heartbeat',time());
rejects(fn()=>returnCreate($dir,$listing,$buyer));
$r=returnCreate($dir,$listing,$owner);check(returnCreate($dir,$listing,$owner)===$r);
check(listingRead($dir)[$listing]['hidden']);
rejects(fn()=>listingVisibility($dir,$listing,$owner,false));rejects(fn()=>purchaseCreate($dir,$listing,$buyer));
$b=['listing'=>$listing,'code'=>$r['code']];
rejects(fn()=>returnUpdate($dir,$b+['status'=>'returned','trade'=>'700']));
returnUpdate($dir,$b+['status'=>'sent','offer'=>'600']);returnUpdate($dir,$b+['status'=>'held']);
rejects(fn()=>returnUpdate($dir,$b+['status'=>'sent','offer'=>'601']));
returnUpdate($dir,$b+['status'=>'failed']);
listingVisibility($dir,$listing,$owner,false);
$purchase=purchaseCreate($dir,$listing,$buyer,static fn($id)=>[['en'=>'Refined Metal']]);rejects(fn()=>returnCreate($dir,$listing,$owner));
purchaseUpdate($dir,['listing'=>$listing,'code'=>$purchase['code'],'status'=>'failed']);
$again=returnCreate($dir,$listing,$owner);check($again['code']!==$r['code']);$b['code']=$again['code'];
returnUpdate($dir,$b+['status'=>'sent','offer'=>'602']);returnUpdate($dir,$b+['status'=>'returned','trade'=>'702']);returnUpdate($dir,$b+['status'=>'returned','trade'=>'702']);
rejects(fn()=>returnUpdate($dir,$b+['status'=>'returned','trade'=>'703']));
rejects(fn()=>returnUpdate($dir,$b+['status'=>'failed']));rejects(fn()=>listingVisibility($dir,$listing,$owner,false));
check(returnCreate($dir,$listing,$owner)['code']===$again['code']);
echo "PASS return ownership, readiness, exclusive purchase/return, idempotency, receipt binding, failed retry, terminal custody\n";
