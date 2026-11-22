<?php
declare(strict_types=1);
function listingHasReturn(array $row): bool {
    foreach($row['returns']??[] as $r)if($r['status']!=='failed')return true;
    return false;
}
function listingVisibility(string $dir,string $code,string $owner,bool $hidden): void {
    listingWrite($dir,static function(&$rows)use($code,$owner,$hidden){
        if(!isset($rows[$code])||$rows[$code]['owner']!==$owner)throw new InvalidArgumentException('본인의 상품만 변경할 수 있습니다.');
        $row=&$rows[$code];
        if(listingHasReturn($row))throw new InvalidArgumentException('반환 진행 중이거나 반환 완료된 상품입니다.');
        if($row['status']!=='published')throw new InvalidArgumentException('입고가 완료된 상품만 변경할 수 있습니다.');
        foreach($row['orders']??[] as $order)if($order['status']!=='failed')throw new InvalidArgumentException('구매 진행 중이거나 판매 완료된 상품은 변경할 수 없습니다.');
        $row['hidden']=$hidden;$row['updated']=time();
    });
}
function listingRead(string $dir): array {
    $file=$dir.'/users/listings.json';
    if(!is_readable(dirname($file)))throw new TradeSettingsException('Listing storage unavailable');
    if(!file_exists($file)){
        if(is_dir($dir.'/users/ledger-backups'))throw new RuntimeException('Operating listing ledger missing; restore required');
        return [];
    }
    $rows=json_decode((string)file_get_contents($file),true,32,JSON_THROW_ON_ERROR);
    if(!is_array($rows))throw new RuntimeException('Invalid listing storage');
    listingBackup($dir,$rows);
    return $rows;
}
function listingBackup(string $dir,array $rows,string $name='ledger'): void {
    if(!in_array($name,['ledger','finance'],true))throw new RuntimeException('Invalid backup name');
    $folder=$dir.'/users/'.$name.'-backups';
    if(!is_dir($folder)&&!mkdir($folder,0700)&&!is_dir($folder))throw new RuntimeException('Backup directory failed');
    $file=$folder.'/'.gmdate('Y-m-d',time()+9*3600).'.txt';
    if(file_exists($file)){
        $saved=json_decode((string)file_get_contents($file),true,8,JSON_THROW_ON_ERROR);
        if(($saved['format']??null)!==1||!is_string($saved['data']??null)||!hash_equals($saved['sha256']??'',hash('sha256',$saved['data'])))throw new RuntimeException('Daily backup checksum mismatch');
        return;
    }
    $data=json_encode($rows,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
    $body=json_encode(['format'=>1,'created_at'=>gmdate('c'),'sha256'=>hash('sha256',$data),'data'=>$data],JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
    $temp=tempnam($folder,'backup-');if($temp===false)throw new RuntimeException('Backup staging failed');
    try {
        if(!chmod($temp,0600))throw new RuntimeException('Backup permissions failed');
        $f=fopen($temp,'wb');if(!$f)throw new RuntimeException('Backup open failed');
        try{if(fwrite($f,$body)!==strlen($body)||!fflush($f)||!fsync($f))throw new RuntimeException('Backup write failed');}finally{fclose($f);}
        if(!@link($temp,$file)&&!file_exists($file))throw new RuntimeException('Backup publish failed');
    }finally{if(file_exists($temp))unlink($temp);}
}
function listingWrite(string $dir,callable $change) {
    $folder=$dir.'/users';$lock=fopen($folder.'/listings.lock','c');
    if(!$lock||!flock($lock,LOCK_EX))throw new RuntimeException('Listing lock failed');
    chmod($folder.'/listings.lock',0600);
    try {
        $rows=listingRead($dir);$result=$change($rows);
        $json=json_encode($rows,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
        $temp=tempnam($folder,'listing-');if($temp===false)throw new RuntimeException('Listing staging failed');
        try {
            chmod($temp,0600);$f=fopen($temp,'wb');if(!$f)throw new RuntimeException('Listing open failed');
            try {if(fwrite($f,$json)!==strlen($json)||!fflush($f)||!fsync($f))throw new RuntimeException('Listing write failed');}finally{fclose($f);}
            if(!rename($temp,$folder.'/listings.json'))throw new RuntimeException('Listing replace failed');
        } finally {if(file_exists($temp))unlink($temp);}
        return $result;
    } finally {flock($lock,LOCK_UN);fclose($lock);}
}
function shopReady(string $dir): bool {
    $stamp=(int)@file_get_contents($dir.'/users/shop-heartbeat');return $stamp<=time()&&$stamp>time()-90;
}
function listingCreate(string $dir,string $owner,array $item,array $price): array {
    if(!shopReady($dir))throw new InvalidArgumentException('입고 봇이 연결되지 않았습니다. 잠시 후 다시 시도하세요.');
    $url=readTradeURL($dir,$owner);if($url==='')throw new InvalidArgumentException('설정에서 본인의 거래 URL을 먼저 등록하세요.');
    if(!preg_match('/\A[1-9][0-9]{0,19}\z/D',(string)($item['assetid']??'')))throw new InvalidArgumentException('백팩 아이템을 다시 선택하세요.');
    return listingWrite($dir,static function(&$rows)use($owner,$item,$price,$url){
        $pending=0;
        foreach($rows as $row){
            if($row['owner']!==$owner||$row['status']==='failed')continue;
            if($row['asset']===$item['assetid']){
                if($row['price']!==$price)throw new InvalidArgumentException('이 아이템은 이미 다른 가격으로 입고 요청되었습니다.');
                return $row;
            }
            if($row['status']!=='published')$pending++;
        }
        if($pending>=10||count($rows)>=5000)throw new InvalidArgumentException('입고 요청 한도에 도달했습니다. 관리자에게 문의하세요.');
        $code=bin2hex(random_bytes(16));
        $row=['code'=>$code,'owner'=>$owner,'asset'=>$item['assetid'],'item'=>$item,'price'=>$price,'url'=>$url,'status'=>'queued','offer'=>'','created'=>time()];
        $rows[$code]=$row;return $row;
    });
}
// Only the authenticated bot API calls this with a verified Steam outcome.
function listingUpdate(string $dir,array $b): array {
    return listingWrite($dir,static function(&$rows)use($b){
        $code=$b['code']??'';
        if(!is_string($code)||!isset($rows[$code]))throw new InvalidArgumentException('Unknown listing');
        $row=&$rows[$code];
        if(($b['owner']??'')!==$row['owner']||($b['asset']??'')!==$row['asset'])throw new InvalidArgumentException('Listing identity mismatch');
        $offer=$b['offer']??'';$status=$b['status']??'';
        if(!is_string($offer)||!preg_match('/\A[1-9][0-9]{0,19}\z/D',$offer)||!in_array($status,['sent','held','published','failed'],true))throw new InvalidArgumentException('Invalid outcome');
        if($row['offer']!==''&&$row['offer']!==$offer)throw new InvalidArgumentException('Conflicting offer');
        foreach($rows as $other)if($other['code']!==$code&&$other['offer']===$offer)throw new InvalidArgumentException('Offer reused');
        if(in_array($row['status'],['published','failed'],true)){
            if($status!==$row['status'])throw new InvalidArgumentException('Terminal outcome conflict');
            if($status==='published'&&(($b['trade']??'')!==$row['trade']||($b['bot_asset']??'')!==$row['bot_asset']))throw new InvalidArgumentException('Receipt conflict');
            return ['ok'=>true];
        }
        if($status==='published'){
            foreach(['trade','bot_asset'] as $k)if(!is_string($b[$k]??null)||!preg_match('/\A[1-9][0-9]{0,19}\z/D',$b[$k]))throw new InvalidArgumentException('Invalid receipt');
            foreach($rows as $other)if($other['code']!==$code&&(($other['trade']??'')===$b['trade']||($other['bot_asset']??'')===$b['bot_asset']))throw new InvalidArgumentException('Receipt reused');
            $row['trade']=$b['trade'];$row['bot_asset']=$b['bot_asset'];
        }
        $row['offer']=$offer;$row['status']=$status;$row['updated']=time();return ['ok'=>true];
    });
}
