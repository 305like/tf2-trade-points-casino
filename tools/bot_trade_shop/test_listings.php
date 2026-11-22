<?php
declare(strict_types=1);
require __DIR__.'/catalog.php';require __DIR__.'/seller.php';require __DIR__.'/settings.php';require __DIR__.'/listings.php';
function check($ok){if(!$ok)throw new RuntimeException('Test failed');}
function rejects($fn){try{$fn();}catch(Throwable $e){return;}throw new RuntimeException('Unsafe operation accepted');}
$dir=sys_get_temp_dir().'/listing-test-'.bin2hex(random_bytes(8));mkdir($dir,0700);mkdir($dir.'/users',0700);
$owner='76561199077147589';$item=['assetid'=>'123','ko'=>'시험','en'=>'Test','image'=>''];$price=sellerPrice(['keys'=>'1','refined'=>'1.55']);
rejects(fn()=>listingCreate($dir,$owner,$item,$price));
file_put_contents($dir.'/users/shop-heartbeat',(string)time());
rejects(fn()=>listingCreate($dir,$owner,$item,$price));
saveTradeURL($dir,$owner,'https://steamcommunity.com/tradeoffer/new/?partner=1116881861&token=Abc_123-');
$row=listingCreate($dir,$owner,$item,$price);check($row['status']==='queued');
check(listingCreate($dir,$owner,$item,$price)['code']===$row['code']);
rejects(fn()=>listingCreate($dir,$owner,$item,sellerPrice(['keys'=>'2','refined'=>'0'])));
$update=['code'=>$row['code'],'owner'=>$owner,'asset'=>'123','offer'=>'234','status'=>'sent'];
rejects(fn()=>listingUpdate($dir,array_replace($update,['owner'=>'76561198000000000'])));
rejects(fn()=>listingUpdate($dir,array_replace($update,['asset'=>'999'])));
listingUpdate($dir,$update);listingUpdate($dir,array_replace($update,['status'=>'held']));
check(listingRead($dir)[$row['code']]['status']==='held');
rejects(fn()=>listingUpdate($dir,array_replace($update,['status'=>'published'])));
$receipt=array_replace($update,['status'=>'published','trade'=>'345','bot_asset'=>'456']);
listingUpdate($dir,$receipt);listingUpdate($dir,$receipt);
check(count(listingRead($dir))===1&&listingRead($dir)[$row['code']]['status']==='published');
rejects(fn()=>listingUpdate($dir,array_replace($receipt,['offer'=>'999'])));
rejects(fn()=>listingUpdate($dir,array_replace($receipt,['bot_asset'=>'999'])));
rejects(fn()=>listingUpdate($dir,array_replace($update,['status'=>'failed'])));
$second=listingCreate($dir,$owner,array_replace($item,['assetid'=>'124']),$price);
rejects(fn()=>listingUpdate($dir,array_replace($receipt,['code'=>$second['code'],'asset'=>'124','offer'=>'235'])));
check((fileperms($dir.'/users/listings.json')&0777)===0600);
$backup=$dir.'/users/ledger-backups/'.gmdate('Y-m-d',time()+9*3600).'.txt';
check(file_exists($backup));$original=file_get_contents($backup);
$saved=json_decode($original,true,8,JSON_THROW_ON_ERROR);
check(hash('sha256',$saved['data'])===$saved['sha256']);
check((fileperms($backup)&0777)===0600);
listingRead($dir);check(file_get_contents($backup)===$original);
rename($dir.'/users/listings.json',$dir.'/users/listings.saved');rejects(fn()=>listingRead($dir));
rename($dir.'/users/listings.saved',$dir.'/users/listings.json');
file_put_contents($backup,'{}');rejects(fn()=>listingRead($dir));file_put_contents($backup,$original);
echo "PASS readiness, URL requirement, idempotent reservation, immutable price/owner/asset/offer, held state, receipt uniqueness, private storage\n";
