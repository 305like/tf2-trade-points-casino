<?php
declare(strict_types=1);
const STEAM_OPENID='https://steamcommunity.com/openid/login';
const SHOP_ORIGIN='https://trade.santasrv.com';
const SHOP_CALLBACK=SHOP_ORIGIN.'/bot-shop/auth.php';

function steamRequest(string $url,?array $post=null,int $limit=8388608): string {
    if(!preg_match('~\Ahttps://steamcommunity\.com/(?:openid/login|inventory/([0-9]+)/440/2\?l=koreana&count=1000(?:&start_assetid=[0-9]+)?)\z~D',$url,$endpoint))throw new RuntimeException('Untrusted Steam endpoint');
    $opts=['method'=>$post===null?'GET':'POST','timeout'=>12,'follow_location'=>0,'ignore_errors'=>true,
        'header'=>"User-Agent: TF2-BotShop/0.2\r\nAccept: application/json,text/plain\r\n"];
    if(!empty($endpoint[1]))$opts['header'].='Referer: https://steamcommunity.com/profiles/'.$endpoint[1]."/inventory\r\n";
    if($post!==null){$opts['content']=http_build_query($post);$opts['header'].="Content-Type: application/x-www-form-urlencoded\r\n";}
    $context=stream_context_create(['http'=>$opts,'ssl'=>['verify_peer'=>true,'verify_peer_name'=>true]]);
    $stream=@fopen($url,'rb',false,$context);
    if(!$stream)throw new RuntimeException('Steam 연결에 실패했습니다. 잠시 후 다시 시도하세요.');
    try {
        $meta=stream_get_meta_data($stream);$status=$meta['wrapper_data'][0]??'';
        if(strpos($status,' 429 ')!==false)throw new RuntimeException('Steam 조회 제한(HTTP 429)입니다. 연속 새로고침하지 말고 몇 분 후 다시 시도하세요.');
        if(strpos($status,' 403 ')!==false)throw new RuntimeException('백팩이 비공개이거나 Steam 접근이 제한되었습니다. 인벤토리 공개 설정을 확인하세요.');
        if(!preg_match('~^HTTP/\S+ 200(?: |$)~',$status)){
            preg_match('~^HTTP/\S+ ([0-9]{3})(?: |$)~',$status,$code);
            throw new RuntimeException('Steam '.(!empty($endpoint[1])?'백팩 조회':'로그인 확인').' 실패 (HTTP '.($code[1]??'unknown').'). 잠시 후 다시 시도하세요.');
        }
        $body=stream_get_contents($stream,$limit+1);
        if($body===false||strlen($body)>$limit)throw new RuntimeException('Steam 응답 크기를 확인할 수 없습니다.');
        return $body;
    } finally {fclose($stream);}
}
function steamCallback(array $params,array $pending,callable $verify,int $now): string {
    if(!isset($pending['state'],$pending['time'])||$now-$pending['time']>600||$now<$pending['time'])throw new RuntimeException('로그인 요청이 만료되었습니다.');
    if(!isset($params['state'])||!hash_equals($pending['state'],$params['state']))throw new RuntimeException('로그인 요청이 일치하지 않습니다.');
    $return=SHOP_CALLBACK.'?state='.$pending['state'];
    if(($params['openid.ns']??'')!=='http://specs.openid.net/auth/2.0'||($params['openid.mode']??'')!=='id_res'
        ||($params['openid.op_endpoint']??'')!==STEAM_OPENID||($params['openid.return_to']??'')!==$return)throw new RuntimeException('Steam 로그인 응답이 올바르지 않습니다.');
    $id=$params['openid.claimed_id']??'';
    if(!preg_match('~\Ahttps://steamcommunity\.com/openid/id/(7656119[0-9]{10})\z~D',$id,$m)||($params['openid.identity']??'')!==$id)throw new RuntimeException('Steam 계정 확인에 실패했습니다.');
    $signed=explode(',',$params['openid.signed']??'');
    foreach(['op_endpoint','claimed_id','identity','return_to','response_nonce','assoc_handle'] as $field)
        if(!in_array($field,$signed,true))throw new RuntimeException('Steam 서명 필드가 누락되었습니다.');
    $nonce=$params['openid.response_nonce']??'';
    if(!preg_match('/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z.+\z/D',$nonce))throw new RuntimeException('Steam 응답 시간이 올바르지 않습니다.');
    $time=strtotime(substr($nonce,0,20));
    if($time===false||$now-$time>600||$time-$now>60)throw new RuntimeException('Steam 응답이 만료되었습니다.');
    $body=[];foreach($params as $key=>$value)if(strpos($key,'openid.')===0)$body[$key]=$value;
    $body['openid.mode']='check_authentication';
    if(!preg_match('/(?:\A|\n)is_valid:true(?:\r?\n|\z)/',$verify($body)))throw new RuntimeException('Steam 서명을 확인하지 못했습니다.');
    return $m[1];
}
function steamUser(): ?string {
    $id=$_SESSION['steamid']??'';
    return is_string($id)&&preg_match('/\A7656119[0-9]{10}\z/D',$id)&&($_SESSION['steam_until']??0)>time()?$id:null;
}
function itemColor($value): string {
    return is_string($value)&&preg_match('/\A[0-9a-fA-F]{6}\z/D',$value)?strtolower($value):'edf0f4';
}
function itemText($value): string {
    return is_string($value)?trim(html_entity_decode(strip_tags(preg_replace('~<br\s*/?>~i',"\n",$value)),ENT_QUOTES|ENT_HTML5,'UTF-8')):'';
}
function inventoryRows(array $data): array {
    if((int)($data['success']??0)!==1)throw new RuntimeException('백팩을 불러오지 못했습니다. 인벤토리 공개 설정을 확인하세요.');
    if(($data['total_inventory_count']??null)===0)return [];
    if(!isset($data['assets'],$data['descriptions'])||!is_array($data['assets'])||!is_array($data['descriptions']))throw new RuntimeException('Steam 백팩 응답에 아이템 정보가 누락되었습니다. 다시 불러오세요.');
    $descriptions=[];
    foreach($data['descriptions']??[] as $d)if((int)($d['appid']??0)===440)$descriptions[$d['classid'].'_'.($d['instanceid']??'0')]=$d;
    $rows=[];
    foreach($data['assets']??[] as $asset) {
        if((int)($asset['appid']??0)!==440||(string)($asset['contextid']??'')!=='2'||(string)($asset['amount']??'')!=='1')continue;
        $id=(string)($asset['assetid']??'');if(!preg_match('/\A[1-9][0-9]{0,19}\z/D',$id))throw new RuntimeException('백팩 아이템 ID 오류');
        $d=$descriptions[$asset['classid'].'_'.($asset['instanceid']??'0')]??null;
        if(!$d)throw new RuntimeException('백팩 아이템 설명을 불러오지 못했습니다.');
        if((int)($d['tradable']??0)!==1)continue;
        $icon=$d['icon_url']??'';
        $details=[];$tags=[];
        foreach(array_merge($d['descriptions']??[],$d['owner_descriptions']??[]) as $line){
            $text=itemText($line['value']??'');
            if($text!=='')$details[]=['text'=>$text,'color'=>itemColor($line['color']??'')];
        }
        foreach($d['tags']??[] as $tag){
            if(!in_array($tag['category']??'',['Quality','Rarity'],true))continue;
            $text=itemText($tag['localized_tag_name']??$tag['name']??'');
            if($text!=='')$tags[]=['text'=>$text,'color'=>itemColor($tag['color']??$d['name_color']??'')];
        }
        $rows[$id]=['assetid'=>$id,'ko'=>(string)($d['name']??$d['market_hash_name']??'TF2 Item'),
            'color'=>itemColor($d['name_color']??''),'type'=>itemText($d['type']??''),'tags'=>$tags,'details'=>$details,
            'en'=>(string)($d['market_hash_name']??$d['name']??'TF2 Item'),
            'image'=>is_string($icon)&&preg_match('~\A[A-Za-z0-9_/-]+\z~D',$icon)?'https://community.akamai.steamstatic.com/economy/image/'.$icon.'/128fx128f':''];
    }
    return $rows;
}
function fetchBackpack(string $id,callable $fetch): array {
    if(!preg_match('/\A7656119[0-9]{10}\z/D',$id))throw new RuntimeException('Steam 본인 확인이 필요합니다.');
    $items=[];$cursor='';$seen=[];
    // Match node-steamcommunity's 1000-item pages; bound work rather than return partial inventories.
    for($page=0;$page<20;$page++) {
        $url='https://steamcommunity.com/inventory/'.$id.'/440/2?l=koreana&count=1000'.($cursor!==''?'&start_assetid='.$cursor:'');
        $data=json_decode($fetch($url),true,32,JSON_THROW_ON_ERROR);
        if(!is_array($data))throw new RuntimeException('백팩 응답 형식 오류');
        foreach(inventoryRows($data) as $asset=>$row){if(isset($items[$asset]))throw new RuntimeException('백팩이 변경되었습니다. 다시 불러오세요.');$items[$asset]=$row;}
        if(empty($data['more_items']))return $items;
        $cursor=(string)($data['last_assetid']??'');
        if(!preg_match('/\A[1-9][0-9]{0,19}\z/D',$cursor)||isset($seen[$cursor]))throw new RuntimeException('백팩 페이지 조회 오류');
        $seen[$cursor]=true;
    }
    throw new RuntimeException('백팩이 조회 한도를 초과했습니다. 일부만 표시하지 않고 조회를 중단했습니다.');
}
