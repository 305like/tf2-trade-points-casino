<?php
declare(strict_types=1);
ini_set('display_errors','0');header('Content-Type: application/json');header('Cache-Control: no-store');
if(($_SERVER['REQUEST_METHOD']??'')!=='POST'){http_response_code(405);exit;}
$root=dirname(__DIR__,2);$hash=@file_get_contents($root.'/.metal-points-private/token.sha256');$token=$_SERVER['HTTP_X_METAL_TOKEN']??'';
if(!$hash||strlen($token)!==64||!hash_equals(trim($hash),hash('sha256',$token))){http_response_code(403);exit;}
require __DIR__.'/settings.php';require __DIR__.'/listings.php';require __DIR__.'/checkout.php';require __DIR__.'/returns.php';$dir=$root.'/.bot-trade-shop-private';
require __DIR__.'/finance.php';
try {
    $raw=file_get_contents('php://input',false,null,0,4097);if(strlen($raw)>4096)throw new InvalidArgumentException('size');
    $b=json_decode($raw,true,16,JSON_THROW_ON_ERROR);if(!is_array($b))throw new InvalidArgumentException('body');
    if($b===['action'=>'finance_queue']){
        financeWalletReconcile($dir);
        $data=financeRead($dir);$requests=array_values(array_filter($data['requests'],static fn($r)=>in_array($r['kind'],['topup','capital_in','capital_out'],true)&&!in_array($r['status'],['completed','failed'],true)));
        $wallet=walletSnapshot();unset($wallet['accounts']);
        $walletPending=count(array_filter($data['requests'],static fn($r)=>$r['kind']==='play_adjust'&&$r['status']==='queued'))>0;
        $ledger=array_values(array_filter($data['requests'],static fn($r)=>in_array($r['kind'],['topup','capital_in','capital_out'],true)));
        echo json_encode(['ok'=>true,'requests'=>$requests,'ledger'=>$ledger,'wallet'=>$wallet,'wallet_pending'=>$walletPending],JSON_THROW_ON_ERROR);
    }elseif(($b['action']??'')==='finance_update'){echo json_encode(financeUpdate($dir,$b),JSON_THROW_ON_ERROR);}
    elseif(($b['action']??'')==='finance_snapshot'){
        if(!is_array($b['report']??null)||!is_array($b['counts']??null))throw new InvalidArgumentException('Finance snapshot');
        $allowed=['total','free','points','pending_withdrawals','seller_payable','capital_in','capital_out','point_deposits','point_returns','capital_used_for_points','capital_used_for_sales','available'];
        if(array_diff(array_keys($b['report']),$allowed)||count($b['report'])!==count($allowed))throw new InvalidArgumentException('Finance fields');
        foreach($b['report'] as $v)if(!is_int($v)||$v<0)throw new InvalidArgumentException('Finance value');
        foreach($b['counts'] as $k=>$v)if(!in_array($k,['Mann Co. Supply Crate Key','Refined Metal','Reclaimed Metal','Scrap Metal'],true)||!is_int($v)||$v<0)throw new InvalidArgumentException('Finance inventory');
        financeWrite($dir,static function(&$d)use($b){$d['snapshot']=['time'=>time(),'report'=>$b['report'],'counts'=>$b['counts']];});echo '{"ok":true}';
    }elseif($b===['action'=>'health']){
        listingRead($dir);$finance=financeRead($dir);$age=time()-($finance['snapshot']['time']??0);
        echo json_encode(['ok'=>true,'ready'=>shopReady($dir),'checkout_ready'=>checkoutReady($dir),'return_ready'=>returnReady($dir),'finance_ready'=>$age>=0&&$age<90,'finance_age'=>$age],JSON_THROW_ON_ERROR);
    } elseif($b===['action'=>'ledger']){
        $rows=[];
        foreach(listingRead($dir) as $r){
            $row=array_intersect_key($r,array_flip(['code','owner','asset','bot_asset','status']));
            $row['orders']=[];$row['returns']=[];
            foreach($r['orders']??[] as $o)$row['orders'][]=array_intersect_key($o,array_flip(['code','listing','seller','buyer','asset','price','status','buy_offer','payout_offer','buy_trade','payout_trade']));
            foreach($r['returns']??[] as $o)$row['returns'][]=array_intersect_key($o,array_flip(['code','listing','owner','asset','status','offer','trade']));
            $rows[]=$row;
        }
        echo json_encode(['ok'=>true,'rows'=>$rows],JSON_THROW_ON_ERROR);
    } elseif($b===['action'=>'queue']){
        $rows=listingRead($dir);$requests=[];
        foreach($rows as $r)if(!in_array($r['status'],['published','failed'],true))$requests[]=['code'=>$r['code'],'owner'=>$r['owner'],'asset'=>$r['asset'],'url'=>$r['url'],'created'=>$r['created']];
        $file=$dir.'/users/shop-heartbeat';if(file_put_contents($file,(string)time(),LOCK_EX)===false)throw new RuntimeException('heartbeat');chmod($file,0600);
        echo json_encode(['ok'=>true,'requests'=>$requests],JSON_THROW_ON_ERROR);
    } elseif($b===['action'=>'purchases']){
        $requests=[];foreach(listingRead($dir) as $r)foreach($r['orders']??[] as $o)if(!in_array($o['status'],['failed','settled','review'],true))$requests[]=$o;
        $file=$dir.'/users/checkout-heartbeat';if(file_put_contents($file,(string)time(),LOCK_EX)===false)throw new RuntimeException('heartbeat');chmod($file,0600);
        echo json_encode(['ok'=>true,'requests'=>$requests],JSON_THROW_ON_ERROR);
    } elseif($b===['action'=>'returns']){
        $requests=[];foreach(listingRead($dir) as $r)foreach($r['returns']??[] as $o)if(!in_array($o['status'],['failed','returned','review'],true))$requests[]=$o;
        $file=$dir.'/users/return-heartbeat';if(file_put_contents($file,(string)time(),LOCK_EX)===false)throw new RuntimeException('heartbeat');chmod($file,0600);
        echo json_encode(['ok'=>true,'requests'=>$requests],JSON_THROW_ON_ERROR);
    } elseif(($b['action']??'')==='return_update'){echo json_encode(returnUpdate($dir,$b),JSON_THROW_ON_ERROR);}
    elseif(($b['action']??'')==='purchase_update'){echo json_encode(purchaseUpdate($dir,$b),JSON_THROW_ON_ERROR);}
    elseif(($b['action']??'')==='update'){echo json_encode(listingUpdate($dir,$b),JSON_THROW_ON_ERROR);}
    else throw new InvalidArgumentException('action');
}catch(InvalidArgumentException|JsonException $e){http_response_code(400);echo '{"ok":false}';}
catch(Throwable $e){http_response_code(503);error_log('Shop bot API storage failure');echo '{"ok":false}';}
