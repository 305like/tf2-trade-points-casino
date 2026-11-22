<?php
$activeListings=array_filter($myListings,static function($listing){
    foreach($listing['returns']??[] as $r)if($r['status']==='returned')return false;
    foreach($listing['orders']??[] as $o)if($o['status']==='settled')return false;
    return true;
});
?>
<section class="panel"><h2>내 상품</h2>
<?php if(!$steamid):?><p>게임에서 !봇거래를 열어 내 상품을 확인하세요.</p>
<?php else:?><p><a href="?tab=my">새로고침</a></p><p class="muted">판매를 중지하면 상점에서 숨겨집니다. 아이템은 봇에 보관되며 다시 판매할 수 있습니다. 아이템 돌려받기를 누르면 판매가 중지되고 본인의 거래 URL로 반환 거래제안을 보냅니다. 열쇠 반환은 주인 승인 후 진행됩니다.</p>
<?php if(!$activeListings):?><p>진행 중인 내 상품이 없습니다.</p><?php endif;?>
<div class="grid"><?php foreach(array_reverse($activeListings) as $listing):
$order=null;foreach($listing['orders']??[] as $candidate)if($candidate['status']!=='failed')$order=$candidate;
$returnRow=null;foreach($listing['returns']??[] as $r)$returnRow=$r;
$hidden=!empty($listing['hidden']);$canChange=$listing['status']==='published'&&!$order&&!listingHasReturn($listing);
$status=$order?purchaseStatus($order['status']):(['queued'=>'입고 거래제안 준비 중','sent'=>'입고 거래제안 수락 대기','held'=>'Steam 거래 보류 중','published'=>$hidden?'판매 중지 · 봇 보관 중':'판매 중','failed'=>'입고 취소·만료'][$listing['status']]??'처리 중');
if(!$order&&$returnRow&&($returnRow['status']!=='failed'||$hidden))$status=returnStatus($returnRow['status']);
?><article class="card"><div class="art"><?php if($listing['item']['image']):?><img src="<?=esc($listing['item']['image'])?>" alt="<?=esc($listing['item']['ko'])?>"><?php endif;?></div><div class="details"><h3><?=esc($listing['item']['ko'])?></h3><p class="price"><?=esc(sellerPriceText($listing['price']))?></p><p><?=esc($status)?></p>
<?php if($canChange):?><form method="post" action="?tab=my"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="listing" value="<?=esc($listing['code'])?>"><button name="action" value="<?=$hidden?'listing_show':'listing_hide'?>"><?=$hidden?'다시 판매':'판매 중지'?></button></form>
<form method="post" action="?tab=my"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="listing" value="<?=esc($listing['code'])?>"><button class="secondary" name="action" value="return_item" <?=$returnReady?'':'disabled'?>><?=$returnReady?'아이템 돌려받기':'반환 봇 연결 대기'?></button></form>
<?php elseif(in_array($listing['status'],['sent','held'],true)&&$listing['offer']!==''):?><a target="_blank" rel="noopener noreferrer" href="https://steamcommunity.com/tradeoffer/<?=esc($listing['offer'])?>/">입고 거래제안 열기</a><?php endif;?>
<?php if($order&&$order['status']==='paid'):?>
<?php if(empty($order['payout_requested'])):?><form method="post" action="?tab=my"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="listing" value="<?=esc($listing['code'])?>"><input type="hidden" name="order" value="<?=esc($order['code'])?>"><button name="action" value="claim_payout">인벤토리로 판매대금 받기</button></form><p class="muted">받기를 누르면 본인에게 키·금속을 보내는 Steam 거래제안을 생성합니다.</p>
<?php else:?><p role="status">판매대금 수령 요청 완료. 거래 가능 여부 및 고액 승인 확인 후 제안을 보냅니다.</p><?php endif;?>
<?php elseif($order&&$order['status']==='settling'&&$order['payout_offer']!==''):?><p><a target="_blank" rel="noopener noreferrer" href="https://steamcommunity.com/tradeoffer/<?=esc($order['payout_offer'])?>/">판매대금 거래제안 열기</a></p><?php endif;?>
<?php if($returnRow&&in_array($returnRow['status'],['sent','held'],true)&&$returnRow['offer']!==''):?><p><a target="_blank" rel="noopener noreferrer" href="https://steamcommunity.com/tradeoffer/<?=esc($returnRow['offer'])?>/">반환 거래제안 열기</a></p><?php endif;?></div></article><?php endforeach;?></div>
<?php endif;?></section>
