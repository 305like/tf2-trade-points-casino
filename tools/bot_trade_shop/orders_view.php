<?php
$activeOrders=array_filter($orders,static fn($o)=>!in_array($o['status'],['settled','failed'],true));
if($tab!=='my'||!$activeOrders)return;
?>
<section class="order-history"><div class="order-heading"><h2>내 구매·정산 진행 상태</h2><a href="?tab=my">새로고침</a></div>
<?php foreach(array_reverse($activeOrders) as $order):?><article class="order-record <?=$order['status']==='settled'?'order-success':''?>"><?php if($order['status']==='settled'):?><span class="order-watermark" aria-hidden="true">거래성공</span><?php endif;?><div class="order-summary"><h3><?=esc($order['name'])?></h3><span><?=esc($steamid===$order['buyer']?'구매':'판매')?> · <?=esc(sellerPriceText($order['price']))?></span></div><p><?=esc(purchaseStatus($order['status']))?></p>
<?php $offer=$steamid===$order['buyer']?$order['buy_offer']:$order['payout_offer'];if($offer!==''):?><a target="_blank" rel="noopener noreferrer" href="https://steamcommunity.com/tradeoffer/<?=esc($offer)?>/">Steam 거래제안 열기</a><?php endif;?>
<?php if($order['status']==='failed'):?><details class="order-help"><summary>취소 안내</summary><p>잔액·금속 구성·거래 가능 여부를 확인하세요. 거래제안 취소·만료도 포함됩니다.</p></details><?php endif;?></article><?php endforeach;?></section>
