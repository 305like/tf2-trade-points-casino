<?php
declare(strict_types=1);
const FINANCE_OWNER='76561198038759714';
function financeOwner(string $id): void {
    if($id!==FINANCE_OWNER)throw new InvalidArgumentException('소유자만 사용할 수 있습니다.');
}
function financeRead(string $dir): array {
    $file=$dir.'/users/finance.json';
    if(!file_exists($file)){
        if(is_dir($dir.'/users/finance-backups'))throw new RuntimeException('Finance ledger missing; restore required');
        return ['requests'=>[],'snapshot'=>[]];
    }
    $data=json_decode((string)file_get_contents($file),true,32,JSON_THROW_ON_ERROR);
    if(!is_array($data['requests']??null)||!is_array($data['snapshot']??null))throw new RuntimeException('Finance ledger invalid');
    listingBackup($dir,$data,'finance');return $data;
}
function financeWrite(string $dir,callable $change){
    $folder=$dir.'/users';$lock=fopen($folder.'/finance.lock','c');
    if(!$lock||!flock($lock,LOCK_EX))throw new RuntimeException('Finance lock failed');
    chmod($folder.'/finance.lock',0600);
    try{
        $data=financeRead($dir);$result=$change($data);
        $body=json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
        $tmp=tempnam($folder,'finance-');if(!$tmp)throw new RuntimeException('Finance staging failed');
        try{
            if(!chmod($tmp,0600))throw new RuntimeException('Finance permissions failed');
            $f=fopen($tmp,'wb');if(!$f)throw new RuntimeException('Finance open failed');
            try{if(fwrite($f,$body)!==strlen($body)||!fflush($f)||!fsync($f))throw new RuntimeException('Finance write failed');}finally{fclose($f);}
            if(!rename($tmp,$folder.'/finance.json'))throw new RuntimeException('Finance publish failed');
        }finally{if(file_exists($tmp))unlink($tmp);}
        return $result;
    }finally{flock($lock,LOCK_UN);fclose($lock);}
}
function walletPath(): string {return getenv('BOTSHOP_WALLET_DIR')?:dirname(__DIR__,2).'/tf/addons/sourcemod/data/metal_points';}
function walletSnapshot(bool $game=false): array {
    $lines=@file(walletPath().($game?'/play.snapshot':'/wallet.snapshot'),FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES);
    if(!$lines||time()-(int)$lines[0]<0||time()-(int)$lines[0]>30)throw new InvalidArgumentException('포인트 장부 연결을 기다리고 있습니다. 잠시 후 다시 시도하세요.');
    $totals=explode(' ',$lines[1]);if(count($totals)!==2)throw new RuntimeException('Wallet totals');
    $accounts=[];foreach(array_slice($lines,2) as $line){$p=explode(' ',$line);if(count($p)!==2||!preg_match('/\A7656119[0-9]{10}\z/D',$p[0])||!ctype_digit($p[1]))throw new RuntimeException('Wallet account');$accounts[$p[0]]=(int)$p[1];}
    return ['points'=>(int)$totals[0],'withdrawals'=>(int)$totals[1],'accounts'=>$accounts];
}
function financeCreate(string $dir,string $owner,string $kind,array $input): array {
    if($kind==='topup')throw new InvalidArgumentException('아이템으로 포인트를 충전할 수 없습니다.');
    if(!preg_match('/\A7656119[0-9]{10}\z/D',$owner))throw new InvalidArgumentException('게임에서 상점을 다시 열어 주세요.');
    if(!in_array($kind,['topup','capital_in','capital_out'],true))throw new InvalidArgumentException('잘못된 요청입니다.');
    if($kind!=='topup')financeOwner($owner);
    $price=sellerPrice($input);$points=$price['keys']*5760+$price['metal_scrap']*10;
    if($points>90000)throw new InvalidArgumentException('한 번에 최대 90,000포인트 상당까지 요청할 수 있습니다.');
    $url=readTradeURL($dir,$owner);if(!$url)throw new InvalidArgumentException('설정에서 본인의 거래 URL을 먼저 등록하세요.');
    return financeWrite($dir,static function(&$data)use($owner,$kind,$price,$url){
        if(time()-($data['snapshot']['time']??0)>60)throw new InvalidArgumentException('자금 봇 연결을 기다리고 있습니다. 잠시 후 다시 시도하세요.');
        foreach($data['requests'] as $r)if($r['owner']===$owner&&!in_array($r['status'],['completed','failed'],true)
            &&!($kind==='capital_in'&&$r['kind']==='capital_out'&&$r['status']==='waiting'))throw new InvalidArgumentException('진행 중인 자금 거래를 먼저 완료하세요.');
        if($kind==='capital_out'){
            if($price['keys']*5760+$price['metal_scrap']*10>($data['snapshot']['report']['available']??0))throw new PurchaseFundsException('유저에게 지급할 금액을 제외한 가용 자금이 부족합니다.');
            $counts=$data['snapshot']['counts'];$left=$price['metal_scrap'];
            foreach(['Refined Metal'=>9,'Reclaimed Metal'=>3,'Scrap Metal'=>1] as $name=>$n)$left-=min($counts[$name]??0,intdiv($left,$n))*$n;
            if($left||($counts['Mann Co. Supply Crate Key']??0)<$price['keys'])throw new PurchaseFundsException('봇이 현재 금속이 부족합니다');
        }
        $code=bin2hex(random_bytes(16));$r=['code'=>$code,'owner'=>$owner,'kind'=>$kind,'price'=>$price,'url'=>$url,'created'=>time(),'status'=>'queued','offer'=>'','trade'=>''];
        $data['requests'][$code]=$r;return $r;
    });
}
function financeUpdate(string $dir,array $b): array {
    return financeWrite($dir,static function(&$data)use($b){
        $code=$b['code']??'';if(!is_string($code)||!isset($data['requests'][$code]))throw new InvalidArgumentException('Unknown finance request');
        $r=&$data['requests'][$code];$status=$b['status']??'';
        $next=['queued'=>['queued','waiting','sent','failed','completed'],'waiting'=>['waiting','sent','failed','completed'],'sent'=>['sent','held','completed','failed'],'held'=>['held','sent','completed','failed'],'completed'=>['completed'],'failed'=>['failed']];
        if(!in_array($status,$next[$r['status']],true))throw new InvalidArgumentException('Finance transition');
        foreach(['offer','trade'] as $key)if(isset($b[$key])){
            if(!is_string($b[$key])||!preg_match('/\A[1-9][0-9]{0,19}\z/D',$b[$key])||($r[$key]&&$r[$key]!==$b[$key]))throw new InvalidArgumentException('Finance identity');
            $r[$key]=$b[$key];
        }
        if($status==='completed'&&(!$r['offer']||!$r['trade']))throw new InvalidArgumentException('Finance receipt required');
        $r['status']=$status;$r['updated']=time();return ['ok'=>true];
    });
}
function financeWallet(string $dir,string $actor,string $kind,array $input): void {
    if($kind!=='play_adjust')throw new InvalidArgumentException('아이템 포인트 충전·출금은 비활성화되었습니다.');
    if(!preg_match('/\A7656119[0-9]{10}\z/D',$actor))throw new InvalidArgumentException('게임에서 상점을 다시 열어 주세요.');
    if(!in_array($kind,['play_adjust','withdraw'],true))throw new InvalidArgumentException('Wallet action');
    $target=$actor;
    if($kind==='play_adjust'){financeOwner($actor);$target=field($input,'target',17);}
    if(!preg_match('/\A7656119[0-9]{10}\z/D',$target))throw new InvalidArgumentException('올바른 SteamID64를 입력하세요.');
    $value=field($input,'points',6);
    if(!preg_match('/\A-?[1-9][0-9]{0,4}\z/D',$value)||abs((int)$value)>90000)throw new InvalidArgumentException('포인트는 -90,000~90,000 범위의 0이 아닌 정수입니다.');
    $amount=(int)$value;$wallet=walletSnapshot(true);
    $url='-';$reason=trim(field($input,'reason',240));
    if($kind==='play_adjust'&&$reason==='')throw new InvalidArgumentException('포인트 변경 사유를 입력하세요.');
    if($kind==='withdraw'){
        if($amount<10||$amount%10!==0)throw new InvalidArgumentException('출금은 10포인트 단위로 입력하세요.');
        if(($wallet['accounts'][$actor]??0)<$amount)throw new PurchaseFundsException('보유 포인트가 부족합니다.');
        $data=financeRead($dir);$snap=$data['snapshot'];
        if(time()-($snap['time']??0)>60)throw new InvalidArgumentException('봇의 자금을 확인하지 못했습니다. 잠시 후 다시 시도하세요.');
        $remaining=$amount;foreach(['Refined Metal'=>90,'Reclaimed Metal'=>30,'Scrap Metal'=>10] as $name=>$n)$remaining-=min($snap['counts'][$name]??0,intdiv($remaining,$n))*$n;
        if($remaining)throw new PurchaseFundsException('봇이 현재 금속이 부족합니다');
        $url=readTradeURL($dir,$actor);if(!$url)throw new InvalidArgumentException('설정에서 본인의 거래 URL을 먼저 등록하세요.');
        $reason='유저 포인트 출금';
    }
    $code=field($input,'nonce',32);if(!preg_match('/\A[a-f0-9]{32}\z/D',$code))throw new InvalidArgumentException('다시 요청하세요.');
    financeWrite($dir,static function(&$d)use($code,$actor,$target,$kind,$amount,$url,$reason){
        if(isset($d['requests'][$code])){
            $old=$d['requests'][$code];
            if($old['owner']!==$actor||$old['target']!==$target||$old['kind']!==$kind||$old['points']!==$amount||$old['reason']!==$reason)throw new InvalidArgumentException('이미 사용된 요청번호입니다.');
            return;
        }
        $d['requests'][$code]=['code'=>$code,'owner'=>$actor,'target'=>$target,'kind'=>$kind,'points'=>$amount,'reason'=>$reason,'url'=>$url,'created'=>time(),'status'=>'queued','offer'=>'','trade'=>''];
    });
    financeWalletPublish($dir,$code);
}
function financeWalletPublish(string $dir,string $code): void {
    $r=financeRead($dir)['requests'][$code];
    $line=implode(' ',[$code,$r['owner'],$r['target'],$r['kind'],$r['points'],$r['created'],$r['url']])."\n";
    $path=walletPath().'/'.$code.'.wallet';
    $done=@file_get_contents($path.'.done');if($done!==false)return;
    if(file_exists($path)){if(file_get_contents($path)!==$line)throw new RuntimeException('Wallet request conflict');return;}
    $temp=tempnam(walletPath(),'wallet-');if(!$temp)throw new RuntimeException('Wallet queue');
    try{if(file_put_contents($temp,$line)!==strlen($line)||!chmod($temp,0644)||!rename($temp,$path))throw new RuntimeException('Wallet queue write');}finally{if(file_exists($temp))unlink($temp);}
}
function financeWalletReconcile(string $dir): void {
    foreach(financeRead($dir)['requests'] as $code=>$r){
        if(!in_array($r['kind'],['play_adjust'],true)||$r['status']!=='queued')continue;
        financeWalletPublish($dir,$code);
        $done=@file(walletPath().'/'.$code.'.wallet.done',FILE_IGNORE_NEW_LINES);
        if(!$done)continue;
        $expected=implode(' ',[$code,$r['owner'],$r['target'],$r['kind'],$r['points'],$r['created'],$r['url']]);
        if(($done[0]??'')!==$expected||!in_array($done[1]??'',['completed','failed'],true))throw new RuntimeException('Wallet receipt mismatch');
        financeWrite($dir,static function(&$d)use($code,$done){$d['requests'][$code]['status']=$done[1];$d['requests'][$code]['updated']=time();});
    }
}
