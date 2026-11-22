<?php if(!isset($tab)||$tab!=='settings')exit; ?>
<section class="panel"><h2>설정 · 내 거래 URL</h2>
<?php if(!$steamid):?>
<p>게임에서 !봇거래를 열어 본인 계정의 거래 URL을 설정하세요.</p>
<?php else:?>
<p><?=$tradeURL!==''?'거래 URL이 등록되어 있습니다. 변경하려면 새 주소를 저장하세요.':'거래 URL이 등록되지 않았습니다. 판매 입고 전에 등록해 주세요.'?></p>
<p><a href="https://steamcommunity.com/my/tradeoffers/privacy" target="_blank" rel="noopener noreferrer">Steam에서 내 거래 URL 확인</a></p>
<form method="post" action="?tab=settings"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><label>내 Steam 거래 URL<input type="url" name="trade_url" maxlength="180" required autocomplete="off" spellcheck="false"></label><p class="muted">Steam에서 복사한 전체 주소를 붙여 넣으세요. 저장된 주소는 공개하거나 채팅에 표시하지 않습니다.</p><button name="action" value="save_trade_url">저장</button></form>
<p><a href="?tab=sell">내 백팩으로 돌아가기</a></p>
<?php endif;?></section>
