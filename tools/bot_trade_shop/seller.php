<?php
declare(strict_types=1);

function sellerPriceText(array $price): string {
    return ((int)$price['keys']>0?$price['keys'].'키 + ':'').$price['refined'].'정';
}

function sellerPrice(array $input): array {
    $keys=field($input,'keys',6);$ref=field($input,'refined',9);
    if(!preg_match('/\A(?:0|[1-9][0-9]{0,5})\z/D',$keys))throw new InvalidArgumentException('키 개수는 0~999999 정수로 입력하세요.');
    if(!preg_match('/\A(0|[1-9][0-9]{0,5})(?:\.(00?|11|22|33|44|55|66|77|88|99))?\z/D',$ref,$m))
        throw new InvalidArgumentException('정제금속 소수부는 .00, .11, .22, .33, .44, .55, .66, .77, .88, .99만 가능합니다.');
    // Integer scrap is authoritative; .99 is nine scrap, never a floating-point fraction.
    $scrap=(int)$m[1]*9+intdiv((int)($m[2]??'0'),11);
    if($scrap>999999*9)throw new InvalidArgumentException('정제금속은 최대 999999정입니다.');
    if((int)$keys===0&&$scrap===0)throw new InvalidArgumentException('판매 가격은 0보다 커야 합니다.');
    $whole=intdiv($scrap,9);$remainder=$scrap%9;
    return ['keys'=>(int)$keys,'metal_scrap'=>$scrap,'refined'=>$whole.($remainder?'.'.str_pad((string)($remainder*11),2,'0',STR_PAD_LEFT):''),
        'whole'=>$whole,'reclaimed'=>intdiv($remainder,3),'scrap'=>$remainder%3];
}
function itemIndex(): array {
    $json=@file_get_contents(__DIR__.'/item-index.json');
    if($json===false)throw new RuntimeException('item index missing');
    $data=json_decode($json,true,16,JSON_THROW_ON_ERROR);
    if(!is_array($data['items']??null)||!count($data['items']))throw new RuntimeException('item index invalid');
    return $data['items'];
}
function searchItems(array $index,string $query): array {
    $query=trim($query);$fold=searchName($query);if($fold==='')return [];
    $result=[];
    foreach($index as $row) {
        if(strpos(searchName($row['ko']),$fold)!==false||strpos(searchName($row['en']),$fold)!==false||strpos(searchName($row['internal']??''),$fold)!==false)$result[]=$row;
    }
    usort($result,static function($a,$b)use($query){
        $ae=strcasecmp($a['en'],$query)===0||$a['ko']===$query;
        $be=strcasecmp($b['en'],$query)===0||$b['ko']===$query;
        return ($be<=>$ae) ?: ((int)$a['id']<=>(int)$b['id']);
    });
    return $result;
}
function searchName(string $name): string {return strtolower(preg_replace('/[\s\p{Pd}]+/u','',$name)??'');}
function selectedItem(array $results,string $id): array {
    foreach($results as $row)if((string)$row['id']===$id)return $row;
    throw new InvalidArgumentException('검색 결과에서 판매할 상품을 선택하세요.');
}
