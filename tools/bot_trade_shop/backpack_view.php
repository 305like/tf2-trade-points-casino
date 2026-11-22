<?php if(!isset($source,$draft))exit; ?>
<?php if(!$steamid):?>
<p>게임 서버에서 !봇거래를 열면 접속한 계정의 백팩을 이용할 수 있습니다.</p>
<?php else:?>
<p>게임에 접속한 Steam 계정: <?=esc($steamid)?></p>
<form method="post" action="?tab=sell&amp;source=backpack"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><button name="action" value="backpack_load" type="submit">내 백팩 불러오기 / 새로고침</button></form>
<p class="muted">Steam 인벤토리가 공개 상태여야 합니다. 30초 간격으로 새로고침할 수 있으며 선택 목록은 5분 동안 유효합니다.</p>
<?php
$cache=$_SESSION['backpack']??[];
if(($cache['owner']??'')===$steamid&&time()-($cache['time']??0)<=300):
$bpQuery=is_string($_GET['bpq']??null)?substr($_GET['bpq'],0,120):'';
$bpItems=array_values(array_filter($cache['items'],static function($r)use($bpQuery){return $bpQuery===''||strpos(searchName($r['ko'].' '.$r['en']),searchName($bpQuery))!==false;}));
$perPage=50;$total=count($bpItems);
$pages=max(1,(int)ceil($total/$perPage));$page=min($pages,max(1,filter_var($_GET['page']??1,FILTER_VALIDATE_INT)?:1));
$pageUrl=static function($number)use($bpQuery){return '?'.http_build_query(['tab'=>'sell','source'=>'backpack','bpq'=>$bpQuery,'page'=>$number]).'#backpack-start';};
?>
<form method="get"><input type="hidden" name="tab" value="sell"><input type="hidden" name="source" value="backpack"><label>내 백팩에서 이름 검색<input name="bpq" maxlength="120" value="<?=esc($bpQuery)?>"></label><button type="submit" class="secondary">백팩 검색</button></form>
<?php require __DIR__.'/backpack_pages.php'; ?>
<?php if(!$bpItems):?><p>거래 가능한 아이템이 없거나 검색 결과가 없습니다.</p><?php else:?>
<form method="post" action="<?=esc($pageUrl($page))?>"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>">
<div class="fields"><label>열쇠 (키) 개수<input name="keys" type="number" min="0" max="999999" step="1" value="<?=esc($draft['keys'])?>" required></label><label>정제금속 가격<input name="refined" type="text" inputmode="decimal" maxlength="9" value="<?=esc($draft['refined'])?>" placeholder="예: 1.55" required></label></div>
<p class="muted">.11 단위로 입력하며 .99는 다음 정제 1개로 올립니다.</p><button id="backpack-start" name="action" value="backpack_preview" type="submit">선택 아이템 · 등록 내용 확인</button>
<fieldset class="backpack-grid"><legend>판매할 아이템 1개 선택</legend>
<?php foreach(array_slice($bpItems,($page-1)*$perPage,$perPage) as $slot=>$row):?><label class="backpack-item"><input type="radio" name="assetid" value="<?=esc($row['assetid'])?>" aria-describedby="item-detail-<?=$slot?>" required><span class="backpack-card"><?=marketIcon($row)?><?php if($row['image']):?><img width="80" height="80" src="<?=esc($row['image'])?>" alt="" loading="lazy"><?php else:?><span class="backpack-no-image">이미지 없음</span><?php endif;?><strong data-color="<?=itemColor($row['color']??'')?>"><?=esc($row['ko'])?></strong><small><?=esc($row['en'])?></small><?php foreach($row['tags']??[] as $tag):?><small data-color="<?=itemColor($tag['color']??'')?>"><?=esc($tag['text'])?></small><?php endforeach;?></span>
<span class="item-tooltip" role="tooltip" id="item-detail-<?=$slot?>"><strong data-color="<?=itemColor($row['color']??'')?>"><?=esc($row['ko'])?></strong><span><?=esc($row['type']??'')?></span><?php foreach($row['details']??[] as $line):?><span data-color="<?=itemColor($line['color']??'')?>"><?=esc($line['text'])?></span><?php endforeach;?><?php if(!isset($row['details'])):?><span>상세 정보를 보려면 백팩을 새로고침해 주세요.</span><?php elseif(!$row['details']&&empty($row['type'])):?><span>Steam에서 제공한 상세 정보가 없습니다.</span><?php endif;?></span></label><?php endforeach;?></fieldset>
<p class="muted">선택한 아이템을 다시 누르면 해제됩니다. 마우스를 올리거나 키보드로 초점을 맞추면 상세 정보를 볼 수 있습니다.</p>
</form>
<?php require __DIR__.'/backpack_pages.php'; ?>
<?php endif;endif;?>
<form method="post" action="auth.php"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><button class="secondary" name="action" value="logout" type="submit">상점 연결 종료</button></form>
<?php endif;?>
