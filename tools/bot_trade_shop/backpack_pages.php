<?php if(!isset($page,$pages,$pageUrl))exit; ?>
<?php
$start=max(1,min($page-2,$pages-4));$end=min($pages,$start+4);
$numbers=array_values(array_unique(array_merge([1],range($start,$end),[$pages])));
?>
<div class="numbered-pages" role="navigation" aria-label="백팩 페이지 이동">
<div class="page-numbers">
<?php if($page>1):?><a class="page-arrow" href="<?=esc($pageUrl($page-1))?>" aria-label="이전 페이지">‹</a><?php endif;?>
<?php $previous=0;foreach($numbers as $target):?>
<?php if($previous&&$target>$previous+1):?><span class="page-gap" aria-hidden="true">…</span><?php endif;?>
<?php if($target===$page):?><span class="page-current" aria-current="page" aria-label="현재 <?=$target?>페이지"><?=$target?></span><?php else:?><a href="<?=esc($pageUrl($target))?>" aria-label="<?=$target?>페이지로 이동"><?=$target?></a><?php endif;?>
<?php $previous=$target;endforeach;?>
<?php if($page<$pages):?><a class="page-arrow" href="<?=esc($pageUrl($page+1))?>" aria-label="다음 페이지">›</a><?php endif;?>
</div>
<div class="page-meta"><small class="page-status">현재 <?=$page?> / 전체 <?=$pages?>페이지</small>
<details class="page-jump"><summary>페이지 직접 이동</summary>
<form method="get" action="#backpack-start"><input type="hidden" name="tab" value="sell"><input type="hidden" name="source" value="backpack"><input type="hidden" name="bpq" value="<?=esc($bpQuery)?>"><input type="number" name="page" aria-label="이동할 페이지" min="1" max="<?=$pages?>" step="1" value="<?=$page?>" required><button type="submit">바로 이동</button></form>
</details>
</div>
</div>
