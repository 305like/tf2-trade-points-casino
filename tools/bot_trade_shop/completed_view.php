<?php
if($tab!=='my'||!$steamid)return;
$history=[];
foreach($myListings as $listing)foreach($listing['returns']??[] as $returned)if($returned['status']==='returned'){
    $history[]=['name'=>$listing['item']['ko'],'kind'=>'아이템 반환','amount'=>'아이템 1개','status'=>'반환 완료 · 내 인벤토리로 돌려받음','stamp'=>'반환완료','time'=>$returned['updated']??$returned['created']];
}
foreach($orders as $order)if(in_array($order['status'],['settled','failed'],true)){
    $success=$order['status']==='settled';
    $history[]=['name'=>$order['name'],'kind'=>$steamid===$order['buyer']?'구매':'판매','amount'=>sellerPriceText($order['price']),'status'=>$success?purchaseStatus('settled'):'구매 취소 · 판매대금 발생 없음','stamp'=>$success?'거래성공':'','time'=>$order['updated']??$order['created']];
}
if(!$history)return;
usort($history,static fn($a,$b)=>$b['time']<=>$a['time']);
?>
<section class="order-history"><div class="order-heading"><h2>완료·취소 내역</h2><a href="?tab=my">새로고침</a></div>
<?php foreach($history as $entry):?><article class="order-record <?=$entry['stamp']!==''?'order-success':''?>">
<?php if($entry['stamp']!==''):?><span class="order-watermark" aria-hidden="true"><?=esc($entry['stamp'])?></span><?php endif;?>
<div class="order-summary"><h3><?=esc($entry['name'])?></h3><span><?=esc($entry['kind'])?> · <?=esc($entry['amount'])?></span></div><p><?=esc($entry['status'])?></p>
</article><?php endforeach;?></section>
