<?php
$ownerPage=$tab==='treasury';
try{
    if(!$steamid)throw new InvalidArgumentException('게임에서 !봇거래를 다시 열어 주세요.');
    if($ownerPage)financeOwner($steamid);
    financeWalletReconcile($dir);$finance=financeRead($dir);$wallet=walletSnapshot(true);
    $balance=$wallet['accounts'][$steamid]??0;
}catch(Throwable $e){?><p class="error"><?=esc($e instanceof InvalidArgumentException?$e->getMessage():'장부를 확인할 수 없습니다. 잠시 후 다시 시도하세요.')?></p><?php return;}
$_SESSION['finance_nonce']??=bin2hex(random_bytes(16));
$nonce=$_SESSION['finance_nonce'];
?>
<section class="panel"><h2><?=$ownerPage?'소유자 자금 관리':'게임 포인트'?></h2>
<p>관리자가 무료로 지급하는 게임 전용 포인트입니다. 아이템 충전·출금·양도·다른 재화로의 교환은 불가능합니다.</p>
<p>내 게임 잔액: <?=esc($balance)?>포인트</p>
<?php if($ownerPage): $report=$finance['snapshot']['report']??[];?>
<p class="muted">운영자 입금은 지급준비금입니다. 유저 포인트는 적립하지 않으며 판매대금 정산과 포인트 출금 부족분에 사용합니다. 출금은 유저 보관 물품과 지급 채무를 제외합니다.</p>
<table><thead><tr><th>장부 항목</th><th>포인트 환산액</th></tr></thead><tbody>
<?php foreach(['total'=>'봇 키·금속 총액','free'=>'보관·거래 예약 제외 금액','points'=>'유저 포인트 잔액 채무','pending_withdrawals'=>'처리 중인 포인트 출금','seller_payable'=>'미지급 판매대금','capital_in'=>'운영자 누적 지급준비금 입금','capital_out'=>'운영자 누적 출금','point_deposits'=>'누적 포인트 충전 수령액','point_returns'=>'누적 포인트 반환 지급액','capital_used_for_points'=>'지급준비금 중 포인트 출금 지급액','capital_used_for_sales'=>'지급준비금 중 판매대금 지급액','available'=>'운영자 출금 가능액 (보수적 계산)'] as $key=>$label):?>
<tr><td><?=esc($label)?></td><td><?=esc($report[$key]??'확인 중')?></td></tr><?php endforeach;?></tbody></table>
<p class="muted">포인트 충전액은 유저에게 반환할 의무가 있는 금액이며 이익이 아닙니다. 도박 수익은 이 장부에 연결하지 않습니다.</p>
<?php endif;?>
<?php foreach($ownerPage?['capital_in'=>'운영자 지급준비금 입금','capital_out'=>'운영자 가용 자금 출금']:[] as $kind=>$label):?>
<form method="post" action="?tab=<?=esc($tab)?>"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="nonce" value="<?=esc($nonce)?>"><input type="hidden" name="action" value="finance"><input type="hidden" name="kind" value="<?=esc($kind)?>">
<h3><?=esc($label)?></h3><div class="price-fields"><label>열쇠 (키) 개수<input name="keys" type="number" min="0" max="15" value="0" required></label><label>정제금속<input name="refined" inputmode="decimal" value="0" required></label></div>
<button type="submit"><?=esc($label)?> 거래제안 요청</button></form>
<?php endforeach;?>
<?php if($ownerPage):?>

<form method="post" action="?tab=treasury"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="nonce" value="<?=esc($nonce)?>"><input type="hidden" name="action" value="finance"><input type="hidden" name="kind" value="play_adjust">
<h3>유저 게임 포인트 수정</h3><label>대상 SteamID64<input name="target" pattern="7656119[0-9]{10}" maxlength="17" required></label><label>변경량 (차감은 음수)<input name="points" type="number" min="-90000" max="90000" required></label><label>변경 사유<input name="reason" maxlength="80" required></label><button type="submit">장부에 기록하고 수정</button></form>
<?php endif;?>
<h3>거래·변경 기록</h3><a href="?tab=<?=esc($tab)?>">새로고침</a>
<?php $labels=['play_adjust'=>'게임 포인트 수정','topup'=>'포인트 충전','capital_in'=>'지급준비금 입금','capital_out'=>'운영자 출금','adjust'=>'포인트 수정','withdraw'=>'포인트 출금 접수'];$states=['queued'=>'처리 대기','waiting'=>'키·금속 부족으로 대기','sent'=>'거래제안 전송','held'=>'Steam 보류','completed'=>'완료','failed'=>'실패'];
foreach(array_slice(array_reverse($finance['requests'],true),0,100,true) as $r):if(!$ownerPage&&$r['owner']!==$steamid)continue;?>
<article><strong><?=esc($labels[$r['kind']]??$r['kind'])?></strong> · <?=esc($states[$r['status']]??$r['status'])?> · <?=isset($r['price'])?esc(sellerPriceText($r['price'])):esc($r['points']).'포인트'?>
<?php if($ownerPage):?><p><?=esc($r['owner'])?><?=isset($r['target'])?' → '.esc($r['target']):''?> · <?=esc($r['reason']??'')?></p><?php endif;?>
<?php if($r['kind']==='withdraw'&&$r['status']==='completed'):?><p>출금 접수가 완료되었습니다. Steam 거래 완료 여부와는 별개입니다.</p><?php endif;?>
<small><?=esc(date('Y-m-d H:i:s',$r['created']))?> · 거래번호 <?=esc($r['trade']?:'미확정')?></small>
<?php if($r['offer']):?><p>Steam 거래제안 번호: <?=esc($r['offer'])?></p><?php endif;?></article>
<?php endforeach;?></section>
