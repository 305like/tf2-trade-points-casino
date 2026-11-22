<?php
// Isolated container fixture only; never deploy this file.
$dir=getenv('BOTSHOP_DATA_DIR');
if(PHP_SAPI!=='cli'||$dir!=='/tmp/botshop-test')exit(1);
mkdir($dir,0700);
mkdir($dir.'/users',0700);
file_put_contents($dir.'/admin-password.hash',password_hash('local-fixture-not-production',PASSWORD_DEFAULT));
if(in_array('--preview',$argv,true)) {
    require __DIR__.'/catalog.php';
    foreach(['공급 상자 열쇠','정제 금속','시험용 모자'] as $i=>$name)
        saveProduct($dir,product(['name'=>'[UI 예시] '.$name,'market'=>'Preview fixture '.($i+1),'image'=>'','buy'=>(string)(100+$i*10),'sell'=>(string)(90+$i*10),'stock'=>'3','buy_enabled'=>'1','sell_enabled'=>'1']));
}
