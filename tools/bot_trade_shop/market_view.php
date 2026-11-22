<?php
require_once __DIR__.'/market.php';
function marketLink(array $item): string {
    static $names=null,$effects=null;
    if($names===null){
        $names=[];
        foreach(json_decode((string)file_get_contents(__DIR__.'/item-index.json'),true)['items'] as $r)$names[$r['en']]=['defindex'=>[(int)$r['id']]];
        $effects=json_decode((string)file_get_contents(__DIR__.'/effect-index.json'),true);
    }
    $id=marketIdentity($item,$names,$effects);
    $qualities=[0=>'Normal',1=>'Genuine',3=>'Vintage',5=>'Unusual',6=>'Unique',11=>'Strange',13=>'Haunted',14=>"Collector's"];
    if($id){
        $quality=$qualities[$id['quality']];$name=$id['base'];$craft=$id['craft'];$effect=$id['effect'];
    }else{
        // A refused automatic quote must not discard a variant's own stats address.
        $name=(string)($item['en']??'');$quality='Unique';$craft=true;$effect=0;
        foreach($qualities as $prefix)if(strpos($name,$prefix.' ')===0){$quality=$prefix;$name=substr($name,strlen($prefix)+1);break;}
        if(strpos($name,'The ')===0&&isset($names[substr($name,4)]))$name=substr($name,4);
        foreach($item['details']??[] as $line){
            $text=$line['text']??'';
            if(preg_match('/제작에 사용(?:할 수 없| 불가)|제작 불가|Not (?:Usable|Usable in|Craftable)|cannot be used in crafting/i',$text))$craft=false;
            if(preg_match('/(?:범상찮은 효과|Unusual Effect):\s*(.+)$/u',$text,$m)){
                foreach($effects as $e)if(trim($m[1])===$e['ko']||trim($m[1])===$e['en']){$effect=(int)$e['id'];break;}
            }
        }
    }
    return 'https://backpack.tf/stats/'.rawurlencode($quality).'/'.rawurlencode($name).'/Tradable/'.($craft?'Craftable':'Non-Craftable').($effect?'/'.$effect:'');
}
function marketIcon(array $item): string {
    foreach($_SESSION['market_items']??[] as $key=>$old)if(($old['until']??0)<time())unset($_SESSION['market_items'][$key]);
    if(count($_SESSION['market_items']??[])>500)$_SESSION['market_items']=[];
    $ref=hash('sha256',json_encode([$item['en']??'',$item['details']??[]]));
    $_SESSION['market_items'][$ref]=['en'=>$item['en']??'','details'=>$item['details']??[],'until'=>time()+1800];
    $url=htmlspecialchars(marketLink($item),ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');
    return '<span class="market-info"><button type="button" class="market-info-button" data-market-url="'.$url.'" data-market-ref="'.$ref.'" aria-label="backpack.tf 시세 보기" title="클릭하면 외부 브라우저용 주소 보기" aria-describedby="market-tip">i</button></span>';
}
