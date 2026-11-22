<?php
declare(strict_types=1);
function returnReady(string $dir): bool {
    $stamp=(int)@file_get_contents($dir.'/users/return-heartbeat');return $stamp<=time()&&$stamp>time()-90;
}
function returnCreate(string $dir,string $listing,string $owner): array {
    if(!returnReady($dir))throw new InvalidArgumentException('반환 봇 연결을 기다리고 있습니다. 잠시 후 다시 시도하세요.');
    $url=readTradeURL($dir,$owner);if($url==='')throw new InvalidArgumentException('설정에서 본인의 거래 URL을 먼저 등록하세요.');
    return listingWrite($dir,static function(&$rows)use($listing,$owner,$url){
        if(!isset($rows[$listing])||$rows[$listing]['owner']!==$owner)throw new InvalidArgumentException('본인의 상품만 돌려받을 수 있습니다.');
        $r=&$rows[$listing];
        if($r['status']!=='published')throw new InvalidArgumentException('입고 완료된 상품만 돌려받을 수 있습니다.');
        foreach($r['orders']??[] as $o)if($o['status']!=='failed')throw new InvalidArgumentException('구매 진행 중이거나 판매된 상품은 반환할 수 없습니다.');
        foreach($r['returns']??[] as $o)if($o['status']!=='failed')return $o;
        if(count($r['returns']??[])>=100)throw new InvalidArgumentException('반환 요청 한도를 초과했습니다. 관리자에게 문의하세요.');
        $code=bin2hex(random_bytes(16));
        $o=['code'=>$code,'listing'=>$listing,'owner'=>$owner,'asset'=>$r['bot_asset'],'url'=>$url,'status'=>'queued','offer'=>'','created'=>time()];
        $r['returns'][$code]=$o;$r['hidden']=true;return $o;
    });
}
function returnUpdate(string $dir,array $b): array {
    return listingWrite($dir,static function(&$rows)use($b){
        $listing=$b['listing']??'';$code=$b['code']??'';
        if(!is_string($listing)||!is_string($code)||!isset($rows[$listing]['returns'][$code]))throw new InvalidArgumentException('Unknown return');
        $r=&$rows[$listing]['returns'][$code];$status=$b['status']??'';
        $allowed=['queued'=>['sent','review'],'sent'=>['sent','held','returned','failed'],'held'=>['held','sent','returned','failed'],'returned'=>['returned'],'failed'=>['failed'],'review'=>['review']];
        if(!in_array($status,$allowed[$r['status']],true))throw new InvalidArgumentException('Invalid return transition');
        foreach(['offer','trade'] as $key)if(isset($b[$key])){
            $v=$b[$key];if(!is_string($v)||!preg_match('/\A[1-9][0-9]{0,19}\z/D',$v))throw new InvalidArgumentException('Invalid receipt');
            if(!empty($r[$key])&&$r[$key]!==$v)throw new InvalidArgumentException('Receipt conflict');
            foreach($rows as $row)foreach($row['returns']??[] as $other)if($other['code']!==$code&&($other[$key]??'')===$v)throw new InvalidArgumentException('Receipt reused');
            $r[$key]=$v;
        }
        if($status!=='review'&&empty($r['offer']))throw new InvalidArgumentException('Offer required');
        if($status==='returned'&&empty($r['trade']))throw new InvalidArgumentException('Completed receipt required');
        $r['status']=$status;$r['updated']=time();return ['ok'=>true];
    });
}
function returnStatus(string $status): string {
    return ['queued'=>'반환 거래제안 준비 중 · 거래 제한 또는 주인 승인 시 대기','sent'=>'반환 거래제안을 보냈습니다. Steam에서 수락하세요.','held'=>'Steam 반환 거래 보류 중','returned'=>'아이템 반환 완료','failed'=>'반환 취소·만료 · 봇 보관 중','review'=>'반환 자동 처리 중지 · 관리자 확인 필요'][$status]??'반환 처리 중';
}
