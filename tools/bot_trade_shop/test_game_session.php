<?php
require __DIR__.'/game-session.php';
$dir=sys_get_temp_dir().'/game-grant-'.bin2hex(random_bytes(8));mkdir($dir,0700);putenv('BOTSHOP_GAME_DIR='.$dir);
$token=str_repeat('a',64);$file=$dir.'/'.$token.'.json';$now=1800000000;
$valid=['steamid'=>'76561198000000000','opened'=>$now-5,'expires'=>$now+15];
function rejected(callable $fn): void {try{$fn();}catch(RuntimeException $e){return;}throw new RuntimeException('Unexpected authorization');}
try {
    file_put_contents($file,json_encode($valid));
    if(shopGameGrant($token,$now)['steamid']!==$valid['steamid'])throw new RuntimeException('Identity mismatch');
    foreach(['','../'.$token,str_repeat('A',64),str_repeat('b',64)] as $bad)rejected(fn()=>shopGameGrant($bad,$now));
    foreach([['expires'=>$now],['expires'=>$now+31],['opened'=>$now+1],['opened'=>$now-1800],['steamid'=>'forged']] as $change){
        file_put_contents($file,json_encode(array_replace($valid,$change)));rejected(fn()=>shopGameGrant($token,$now));
    }
    unlink($file);rejected(fn()=>shopGameGrant($token,$now));
    echo "PASS game grant identity, expiry, lease bound, window lifetime, deletion and path validation\n";
} finally {if(file_exists($file))unlink($file);rmdir($dir);}
