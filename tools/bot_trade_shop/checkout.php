<?php
declare(strict_types=1);
class PurchaseFundsException extends InvalidArgumentException {}
function purchaseFunds(array $items,array $price): bool {
    $counts=['Mann Co. Supply Crate Key'=>0,'Refined Metal'=>0,'Reclaimed Metal'=>0,'Scrap Metal'=>0];
    foreach($items as $item){$name=$item['en']??'';if(isset($counts[$name]))$counts[$name]++;}
    if($counts['Mann Co. Supply Crate Key']<$price['keys'])return false;
    $remaining=$price['metal_scrap'];
    foreach(['Refined Metal'=>9,'Reclaimed Metal'=>3,'Scrap Metal'=>1] as $name=>$value)$remaining-=min($counts[$name],intdiv($remaining,$value))*$value;
    return $remaining===0;
}
function checkoutReady(string $dir): bool {
    $stamp=(int)@file_get_contents($dir.'/users/checkout-heartbeat');return $stamp<=time()&&$stamp>time()-90;
}
function purchaseCreate(string $dir,string $listing,string $buyer,?callable $inventory=null): array {
    if(!checkoutReady($dir))throw new InvalidArgumentException('구매 봇 연결을 기다리고 있습니다. 잠시 후 다시 시도하세요.');
    $url=readTradeURL($dir,$buyer);if($url==='')throw new InvalidArgumentException('설정에서 본인의 거래 URL을 먼저 등록하세요.');
    $snapshot=listingRead($dir)[$listing]??null;
    if(!$snapshot||$snapshot['status']!=='published'||!empty($snapshot['hidden'])||listingHasReturn($snapshot))throw new InvalidArgumentException('구매할 수 없는 상품입니다.');
    if($snapshot['owner']===$buyer)throw new InvalidArgumentException('본인의 상품은 구매할 수 없습니다.');
    foreach($snapshot['orders']??[] as $order)if($order['status']!=='failed'){
        if($order['buyer']===$buyer)return $order;
        throw new InvalidArgumentException('이미 다른 구매자가 거래 중이거나 판매된 상품입니다.');
    }
    // Inspect current tradable inventory before reserving a listing; never hold the ledger lock during Steam I/O.
    try{$items=$inventory?$inventory($buyer):fetchBackpack($buyer,static fn($url)=>steamRequest($url));}
    catch(Throwable $e){throw new InvalidArgumentException('백팩의 키·금속을 확인하지 못했습니다. 인벤토리 공개 설정을 확인한 뒤 다시 시도하세요.');}
    if(!purchaseFunds($items,$snapshot['price']))throw new PurchaseFundsException('키·금속이 부족하거나 정확한 금속 구성이 없습니다. 백팩을 확인해 주세요.');
    return listingWrite($dir,static function(&$rows)use($dir,$listing,$buyer,$url,$snapshot){
        if(!isset($rows[$listing])||$rows[$listing]['status']!=='published'||!empty($rows[$listing]['hidden'])||listingHasReturn($rows[$listing]))throw new InvalidArgumentException('구매할 수 없는 상품입니다.');
        $r=&$rows[$listing];
        if($r['price']!==$snapshot['price'])throw new InvalidArgumentException('가격이 변경되었습니다. 다시 확인하세요.');
        if($r['owner']===$buyer)throw new InvalidArgumentException('본인의 상품은 구매할 수 없습니다.');
        foreach($r['orders']??[] as $order)if($order['status']!=='failed'){
            if($order['buyer']===$buyer)return $order;
            throw new InvalidArgumentException('이미 다른 구매자가 거래 중이거나 판매된 상품입니다.');
        }
        $pending=0;
        foreach($rows as $other)foreach($other['orders']??[] as $o)if($o['buyer']===$buyer&&!in_array($o['status'],['failed','settled'],true))$pending++;
        if($pending>=5)throw new InvalidArgumentException('진행 중인 구매를 먼저 완료하세요.');
        $sellerURL=readTradeURL($dir,$r['owner']);if($sellerURL==='')throw new InvalidArgumentException('판매자의 정산 URL을 확인할 수 없습니다.');
        $code=bin2hex(random_bytes(16));
        $o=['code'=>$code,'listing'=>$listing,'buyer'=>$buyer,'buyer_url'=>$url,'seller'=>$r['owner'],'seller_url'=>$sellerURL,'asset'=>$r['bot_asset'],'price'=>$r['price'],'status'=>'queued','created'=>time(),'buy_offer'=>'','payout_offer'=>''];
        $r['orders'][$code]=$o;return $o;
    });
}
function purchaseUpdate(string $dir,array $body): array {
    return listingWrite($dir,static function(&$rows)use($body){
        $listing=$body['listing']??'';$code=$body['code']??'';
        if(!is_string($listing)||!is_string($code)||!isset($rows[$listing]['orders'][$code]))throw new InvalidArgumentException('Unknown order');
        $o=&$rows[$listing]['orders'][$code];$status=$body['status']??'';
        $next=['queued'=>['sent','failed'],'sent'=>['sent','held','paid','failed'],'held'=>['held','sent','paid','failed'],'paid'=>['paid','settling','review'],'settling'=>['settling','settled','review'],'review'=>['review'],'settled'=>['settled'],'failed'=>['failed']];
        if(!in_array($status,$next[$o['status']],true))throw new InvalidArgumentException('Invalid transition');
        if($status==='settling'&&$o['status']==='paid'&&empty($o['payout_requested']))throw new InvalidArgumentException('Seller claim required');
        foreach(['buy_offer','payout_offer','buy_trade','payout_trade'] as $k)if(isset($body[$k])){
            $v=$body[$k];if(!is_string($v)||!preg_match('/\A[1-9][0-9]{0,19}\z/D',$v))throw new InvalidArgumentException('Invalid receipt');
            if(!empty($o[$k])&&$o[$k]!==$v)throw new InvalidArgumentException('Receipt conflict');
            foreach($rows as $r)foreach($r['orders']??[] as $other)foreach(['buy_offer','payout_offer','buy_trade','payout_trade'] as $field)
                if(str_ends_with($field,'offer')===str_ends_with($k,'offer')&&($other['code']!==$code||$field!==$k)&&($other[$field]??'')===$v)throw new InvalidArgumentException('Receipt reused');
            $o[$k]=$v;
        }
        if(in_array($status,['sent','held','paid','settling','settled','review'],true)&&empty($o['buy_offer']))throw new InvalidArgumentException('Offer required');
        if(in_array($status,['paid','settling','settled','review'],true)&&empty($o['buy_trade']))throw new InvalidArgumentException('Completed purchase required');
        if(in_array($status,['settling','settled'],true)&&empty($o['payout_offer']))throw new InvalidArgumentException('Payout required');
        if($status==='settled'&&empty($o['payout_trade']))throw new InvalidArgumentException('Completed payout required');
        $o['status']=$status;$o['updated']=time();
        return ['ok'=>true];
    });
}
function purchaseClaim(string $dir,string $listing,string $code,string $seller): array {
    return listingWrite($dir,static function(&$rows)use($dir,$listing,$code,$seller){
        if(!isset($rows[$listing]['orders'][$code])||$rows[$listing]['owner']!==$seller||$rows[$listing]['orders'][$code]['seller']!==$seller)throw new InvalidArgumentException('본인의 판매대금만 받을 수 있습니다.');
        $o=&$rows[$listing]['orders'][$code];
        if(in_array($o['status'],['settling','settled'],true))return $o;
        if($o['status']!=='paid')throw new InvalidArgumentException('구매 거래가 완료된 후 판매대금을 받을 수 있습니다.');
        if(!empty($o['payout_requested']))return $o;
        $url=readTradeURL($dir,$seller);if($url==='')throw new InvalidArgumentException('설정에서 본인의 거래 URL을 먼저 등록하세요.');
        $o['seller_url']=$url;$o['payout_requested']=true;$o['updated']=time();return $o;
    });
}
function purchaseStatus(string $status): string {
    return ['queued'=>'구매 거래제안 준비 중','sent'=>'구매 거래제안을 보냈습니다. Steam에서 수락하세요.','held'=>'구매 거래 보류 중','paid'=>'판매되었습니다. 판매대금 수령 대기','settling'=>'판매되었습니다. 판매대금 거래제안 수락 대기','settled'=>'판매되었습니다. 판매대금 수령 완료','failed'=>'구매 취소 · 판매대금 발생 없음','review'=>'판매되었습니다. 정산 관리자 확인 필요'][$status]??'처리 중';
}
