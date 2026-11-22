<?php
declare(strict_types=1);

function marketIdentity(array $row,array $prices,array $effects): ?array {
    $name=$row['en']??'';$quality=6;
    foreach(['Strange'=>11,'Unusual'=>5,'Vintage'=>3,'Genuine'=>1,'Haunted'=>13,"Collector's"=>14,'Normal'=>0] as $prefix=>$q){
        if(strpos($name,$prefix.' ')===0){$quality=$q;$name=substr($name,strlen($prefix)+1);break;}
    }
    // These variants need their own price identity; never substitute a plain item's price.
    if(preg_match('/^(?:Strange |Unusual |(?:Professional |Specialized )?Killstreak |Australium )|\((?:Factory New|Minimal Wear|Field-Tested|Well-Worn|Battle Scarred)\)$/',$name))return null;
    $base=isset($prices[$name])?$name:(strpos($name,'The ')===0?substr($name,4):'');
    if(!isset($prices[$base]))return null;
    $effect=0;$effectName='';$craft=true;
    foreach($row['details']??[] as $line){
        $text=$line['text']??'';
        if(preg_match('/제작에 사용(?:할 수 없| 불가)|제작 불가|Not (?:Usable|Usable in|Craftable)|cannot be used in crafting/i',$text))$craft=false;
        if(preg_match('/(?:범상찮은 효과|Unusual Effect):\s*(.+)$/u',$text,$m)){
            foreach($effects as $e)if(trim($m[1])===$e['ko']||trim($m[1])===$e['en']){$effect=(int)$e['id'];$effectName=$e['en'];break;}
        }
    }
    if($quality===5&&!$effect)return null;
    $prefix=[0=>'Normal ',1=>'Genuine ',3=>'Vintage ',5=>$effectName.' ',6=>'',11=>'Strange ',13=>'Haunted ',14=>"Collector's "][$quality];
    return ['base'=>$base,'quality'=>$quality,'effect'=>$effect,'craft'=>$craft,'sku'=>($craft?'':'Non-Craftable ').$prefix.$name,'defs'=>$prices[$base]['defindex']??[]];
}
function marketNumber($n): ?float {return is_numeric($n)&&is_finite((float)$n)&&(float)$n>=0&&(float)$n<100000000?(float)$n:null;}
function marketAmount(array $p): ?string {
    $units=['keys'=>'키','metal'=>'정','usd'=>'USD'];$currency=$p['currency']??'';
    $low=marketNumber($p['value']??null);$high=marketNumber($p['value_high']??$p['value']??null);
    if(!isset($units[$currency])||$low===null||$high===null||$high<$low)return null;
    return $low.($high>$low?'–'.$high:'').' '.$units[$currency];
}
function marketQuote(array $id,array $prices,array $snapshot,int $now): array {
    $entry=$prices[$id['base']]['prices'][$id['quality']]['Tradable'][$id['craft']?'Craftable':'Non-Craftable'][$id['effect']]??[];
    $result=['name'=>$id['sku'],'suggested'=>marketAmount($entry),'price_updated'=>(int)($entry['last_update']??0),'sell'=>null,'buy'=>null,'checked'=>$now,'orders_ok'=>isset($snapshot['listings'])&&is_array($snapshot['listings'])];
    $key=$prices['Mann Co. Supply Crate Key']['prices'][6]['Tradable']['Craftable'][0]??[];
    $rate=($key['currency']??'')==='metal'?marketNumber($key['value_raw']??$key['value']??null):null;
    $best=[];
    foreach($snapshot['listings']??[] as $r){
        $side=$r['intent']??'';$item=$r['item']??[];
        if(!in_array($side,['buy','sell'],true)||!in_array((int)($item['defindex']??-1),array_map('intval',$id['defs']),true)||(int)($item['quality']??-1)!==$id['quality'])continue;
        if(!empty($item['flag_cannot_trade'])||(!empty($item['flag_cannot_craft']))===$id['craft'])continue;
        $effect=0;$special=false;
        foreach($item['attributes']??[] as $a){
            if(in_array((int)$a['defindex'],[134,2041],true))$effect=(int)((int)$a['defindex']===2041?$a['value']:($a['float_value']??0));
            if(in_array((int)$a['defindex'],[2025,2027,834,725],true))$special=true;
        }
        if($effect!==$id['effect']||$special)continue;
        $c=$r['currencies']??[];
        if(array_diff(array_keys($c),['keys','metal']))continue;
        $keys=marketNumber($c['keys']??0);$metal=marketNumber($c['metal']??0);
        if($keys===null||$metal===null||($keys===0.0&&$metal===0.0)||($keys>0&&$rate===null))continue;
        $value=$keys*($rate??0)+$metal;
        if(isset($best[$side])&&($side==='sell'?$value>=$best[$side]:$value<=$best[$side]))continue;
        $best[$side]=$value;$result[$side]=($keys>0?$keys.'키':'').($keys>0&&$metal>0?' + ':'').($metal>0?$metal.'정':'');
    }
    return $result;
}
function marketRequest(array $config,string $kind,string $sku=''): array {
    if(!in_array($kind,['prices','orders'],true))throw new RuntimeException('Market kind');
    $params=$kind==='prices'?['appid'=>440,'raw'=>1,'key'=>$config['apiKey']]:['appid'=>440,'sku'=>$sku];
    $url='https://api.backpack.tf/api/'.($kind==='prices'?'IGetPrices/v4':'classifieds/listings/snapshot').'?'.http_build_query($params);
    $header="Accept: application/json\r\nUser-Agent: TF2-BotShop/1.0\r\n";
    if($kind==='orders'){
        if(!is_string($config['accessToken']??null)||preg_match('/[\r\n]/',$config['accessToken']))throw new RuntimeException('Market config');
        $header.='X-Auth-Token: '.$config['accessToken']."\r\n";
    }
    $ctx=stream_context_create(['http'=>['timeout'=>10,'follow_location'=>0,'ignore_errors'=>true,'header'=>$header],'ssl'=>['verify_peer'=>true,'verify_peer_name'=>true]]);
    $f=@fopen($url,'rb',false,$ctx);if(!$f)throw new RuntimeException('Market connection');
    try{
        $status=stream_get_meta_data($f)['wrapper_data'][0]??'';
        if(!preg_match('~^HTTP/\S+ 200(?: |$)~',$status))throw new RuntimeException('Market upstream');
        $body=stream_get_contents($f,20971521);
        if($body===false||strlen($body)>20971520)throw new RuntimeException('Market size');
        return json_decode($body,true,32,JSON_THROW_ON_ERROR);
    }finally{fclose($f);}
}
function marketSave(string $path,array $data): void {
    $tmp=tempnam(dirname($path),'market-');if($tmp===false)throw new RuntimeException('Market cache');
    try{chmod($tmp,0600);$body=json_encode($data,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);if(file_put_contents($tmp,$body)!==strlen($body)||!rename($tmp,$path))throw new RuntimeException('Market cache');}
    finally{if(file_exists($tmp))unlink($tmp);}
}
function marketLoad(string $path): array {
    if(!is_file($path))return [];
    $data=json_decode((string)file_get_contents($path),true,32);return is_array($data)?$data:[];
}
function marketFetch(string $dir,array $row,?callable $fetch=null): array {
    $folder=$dir.'/users';$hash=hash('sha256',json_encode([$row['en']??'',$row['details']??[]]));
    // Fixed cache slots bound disk growth even across many different backpacks.
    $path=$folder.'/market-'.substr($hash,0,2).'.json';$cached=marketLoad($path);
    if(($cached['key']??'')===$hash&&($cached['until']??0)>time())return $cached['quote'];
    $lock=fopen($folder.'/market.lock','c');if(!$lock)throw new RuntimeException('Market lock');chmod($folder.'/market.lock',0600);
    try{
        if(!flock($lock,LOCK_EX|LOCK_NB))throw new RuntimeException('Market busy');
        $stamp=$folder.'/market-request-time';$last=(int)@file_get_contents($stamp);
        if(time()-$last<3)throw new RuntimeException('Market busy');
        file_put_contents($stamp,(string)time());chmod($stamp,0600);
        $config=marketLoad($folder.'/market-config.json');
        if(!preg_match('/\A[a-f0-9]{24,64}\z/iD',$config['apiKey']??''))throw new RuntimeException('Market unavailable');
        $fetch=$fetch??static function($kind,$sku='')use($config){return marketRequest($config,$kind,$sku);};
        $all=marketLoad($folder.'/market-prices.json');
        if(($all['until']??0)<time()){
            $body=$fetch('prices');$p=$body['response']??[];
            if(($p['success']??0)!=1||!is_array($p['items']??null))throw new RuntimeException('Market prices');
            $all=['until'=>time()+3600,'items'=>$p['items']];marketSave($folder.'/market-prices.json',$all);
        }
        $effects=json_decode((string)file_get_contents(__DIR__.'/effect-index.json'),true,16,JSON_THROW_ON_ERROR);
        $id=marketIdentity($row,$all['items'],$effects);
        if(!$id)$quote=['unavailable'=>'품질·효과·도색까지 일치하는 시세를 확인할 수 없습니다.'];
        else {
            try{$snapshot=$fetch('orders',$id['sku']);}catch(Throwable $e){$snapshot=[];}
            if(($snapshot['appid']??null)!==440||($snapshot['sku']??null)!==$id['sku'])$snapshot=[];
            $quote=marketQuote($id,$all['items'],$snapshot,time());
        }
        marketSave($path,['key'=>$hash,'until'=>time()+300,'quote'=>$quote]);return $quote;
    }finally{flock($lock,LOCK_UN);fclose($lock);}
}
