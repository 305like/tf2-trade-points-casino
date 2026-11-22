<?php
require __DIR__.'/catalog.php';require __DIR__.'/seller.php';require __DIR__.'/settings.php';require __DIR__.'/listings.php';require __DIR__.'/checkout.php';require __DIR__.'/finance.php';
function check($v){if(!$v)throw new RuntimeException('assertion');}
function denied(callable $f){try{$f();}catch(InvalidArgumentException $e){return;}throw new RuntimeException('Expected rejection');}
$dir=sys_get_temp_dir().'/finance-'.bin2hex(random_bytes(8));mkdir($dir);mkdir($dir.'/users',0700);mkdir($dir.'/wallet',0700);putenv('BOTSHOP_WALLET_DIR='.$dir.'/wallet');
$owner=FINANCE_OWNER;$user='76561199077147589';
saveTradeURL($dir,$owner,'https://steamcommunity.com/tradeoffer/new/?partner=78493986&token=Abc_123-');
file_put_contents($dir.'/wallet/play.snapshot',time()."\n90 0\n$owner 90\n");
financeWrite($dir,static function(&$d){$d['snapshot']=['time'=>time(),'counts'=>[],'report'=>[]];});
denied(fn()=>financeCreate($dir,$user,'capital_in',['keys'=>'0','refined'=>'1']));
$row=financeCreate($dir,$owner,'capital_in',['keys'=>'1','refined'=>'1.11']);check($row['price']['metal_scrap']===10);
denied(fn()=>financeUpdate($dir,['code'=>$row['code'],'status'=>'completed']));
financeUpdate($dir,['code'=>$row['code'],'status'=>'completed','offer'=>'123','trade'=>'456']);
$b=['nonce'=>str_repeat('a',32),'points'=>'90','reason'=>''];
denied(fn()=>financeWallet($dir,$owner,'withdraw',$b));
denied(fn()=>financeCreate($dir,$owner,'topup',['keys'=>'0','refined'=>'1']));
check(!file_exists($dir.'/wallet/'.$b['nonce'].'.wallet'));
denied(fn()=>financeWallet($dir,$user,'play_adjust',['nonce'=>str_repeat('b',32),'target'=>$owner,'points'=>'90','reason'=>'fixture']));
financeWallet($dir,$owner,'play_adjust',['nonce'=>str_repeat('b',32),'target'=>$user,'points'=>'90','reason'=>'fixture']);
$request=file_get_contents($dir.'/wallet/'.str_repeat('b',32).'.wallet');
financeWallet($dir,$owner,'play_adjust',['nonce'=>str_repeat('b',32),'target'=>$user,'points'=>'90','reason'=>'fixture']);
check(file_get_contents($dir.'/wallet/'.str_repeat('b',32).'.wallet')===$request);
file_put_contents($dir.'/wallet/'.str_repeat('b',32).'.wallet.done',$request."completed\n");financeWalletReconcile($dir);
check(financeRead($dir)['requests'][str_repeat('b',32)]['status']==='completed');
check(is_dir($dir.'/users/finance-backups'));
echo "PASS owner gate, verified capital receipt, shortage without debit, idempotent wallet mailbox, audit and daily backup\n";
