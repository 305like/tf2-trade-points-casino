<?php if(!isset($preview)||!$preview)exit; ?>
<div class="confirm-overlay"><section class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title" tabindex="-1">
<h2 id="confirm-title">이 아이템을 등록하시겠습니까?</h2>
<?php if($preview['item']['image']):?><img width="128" height="128" src="<?=esc($preview['item']['image'])?>" alt="<?=esc($preview['item']['ko'])?>"><?php endif;?>
<h3><?=esc($preview['item']['ko'])?></h3><p class="muted"><?=esc($preview['item']['en'])?></p>
<p class="price"><?=esc(sellerPriceText($preview['price']))?></p>
<p class="muted">금속 구성: <?=esc($preview['price']['whole'])?>정제 + <?=esc($preview['price']['reclaimed'])?>재활용 + <?=esc($preview['price']['scrap'])?>폐기</p>
<p>확인하면 봇이 입고 거래제안을 보냅니다. 실제 수령 후 상품이 공개됩니다.</p>
<?php if($tradeURL===''):?><a href="?tab=settings">설정에서 거래 URL을 먼저 등록하세요.</a><?php elseif(!$intakeReady):?><p role="status">입고 봇 연결을 기다리고 있습니다.</p><?php endif;?>
<form method="post" action="?tab=sell"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="confirmation" value="<?=esc($_SESSION['listing_preview']['nonce'])?>"><button name="action" value="register_item" <?=$intakeReady&&$tradeURL!==''?'':'disabled'?>>확인 · 입고 거래제안 요청</button> <a class="confirm-cancel" href="?tab=sell">취소</a></form>
</section></div>
