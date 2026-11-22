<?php
declare(strict_types=1);
function esc($v): string{return htmlspecialchars((string)$v,ENT_QUOTES,'UTF-8');}
$bpQuery='token';$pageUrl=static function($n){return '?page='.$n.'&bpq=token';};
foreach([[1,100,[1,2,3,4,5,100]],[50,100,[1,48,49,50,51,52,100]],[100,100,[1,96,97,98,99,100]],[1,1,[1]],[2,3,[1,2,3]]] as [$page,$pages,$expected]){
    ob_start();require __DIR__.'/backpack_pages.php';$html=ob_get_clean();
    if($numbers!==$expected||substr_count($html,'aria-current="page"')!==1)throw new RuntimeException('Invalid page numbers');
    if((strpos($html,'aria-label="이전 페이지"')!==false)!==($page>1))throw new RuntimeException('Invalid previous link');
    if((strpos($html,'aria-label="다음 페이지"')!==false)!==($page<$pages))throw new RuntimeException('Invalid next link');
    if(strpos($html,'name="bpq" value="token"')===false)throw new RuntimeException('Lost search');
}
echo "PASS first/middle/last/single page, current marker, arrows and search preservation\n";
