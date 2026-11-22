<?php
declare(strict_types=1);
require __DIR__.'/steam.php';
function check(bool $v): void{if(!$v)throw new RuntimeException('test failed');}
function fails(callable $fn): void{try{$fn();}catch(Throwable $e){return;}throw new RuntimeException('invalid operation accepted');}
$now=time();$pending=['state'=>str_repeat('a',48),'time'=>$now];$id='76561199077147589';
$signed='op_endpoint,claimed_id,identity,return_to,response_nonce,assoc_handle';
$p=['state'=>$pending['state'],'openid.ns'=>'http://specs.openid.net/auth/2.0','openid.mode'=>'id_res',
    'openid.op_endpoint'=>STEAM_OPENID,'openid.return_to'=>SHOP_CALLBACK.'?state='.$pending['state'],
    'openid.claimed_id'=>'https://steamcommunity.com/openid/id/'.$id,'openid.identity'=>'https://steamcommunity.com/openid/id/'.$id,
    'openid.signed'=>$signed,'openid.sig'=>'test','openid.assoc_handle'=>'test','openid.response_nonce'=>gmdate('Y-m-d\TH:i:s\Z',$now).'test'];
$verify=static function($b){check($b['openid.mode']==='check_authentication');return "ns:http://specs.openid.net/auth/2.0\nis_valid:true\n";};
check(steamCallback($p,$pending,$verify,$now)===$id);
foreach(['state'=>'bad','openid.op_endpoint'=>'https://evil.test','openid.identity'=>'https://steamcommunity.com/openid/id/76561198000000000',
         'openid.return_to'=>'https://evil.test','openid.signed'=>'identity','openid.response_nonce'=>'2000-01-01T00:00:00Zold'] as $key=>$value)
    fails(static function()use($p,$key,$value,$pending,$verify,$now){steamCallback(array_replace($p,[$key=>$value]),$pending,$verify,$now);});
fails(static function()use($p,$pending,$now){steamCallback($p,$pending,static function(){return "is_valid:false\n";},$now);});
fails(static function()use($p,$verify,$now){steamCallback($p,[],$verify,$now);});
fails(static function()use($p,$pending,$verify,$now){steamCallback($p,$pending,$verify,$now+601);});
$d=['appid'=>440,'classid'=>'12','instanceid'=>'0','tradable'=>1,'name'=>'병과 토큰 - 스나이퍼','market_hash_name'=>'Class Token - Sniper','icon_url'=>'abc_123'];
$a=['appid'=>440,'contextid'=>'2','classid'=>'12','instanceid'=>'0','assetid'=>'123','amount'=>'1'];
$page=['success'=>1,'assets'=>[$a],'descriptions'=>[$d]];
check(inventoryRows($page)[123]['en']==='Class Token - Sniper');
$rich=$page;$rich['descriptions'][0]+= ['name_color'=>'8650AC','type'=>'Level 10 Hat','tags'=>[['category'=>'Quality','localized_tag_name'=>'Unusual','color'=>'8650AC'],['category'=>'Rarity','localized_tag_name'=>'Assassin','color'=>'D32CE6']], 'descriptions'=>[['value'=>'Paint: Pink<br>Part: Kills','color'=>'FFD700'],['value'=>'<img src=x onerror=alert(1)>Safe','color'=>'red;display:none']]];
$detail=inventoryRows($rich)[123];
check($detail['color']==='8650ac'&&$detail['type']==='Level 10 Hat');
check(count($detail['tags'])===2&&$detail['tags'][1]['color']==='d32ce6');
check($detail['details'][0]['text']==="Paint: Pink\nPart: Kills"&&$detail['details'][1]['text']==='Safe');
check($detail['details'][1]['color']==='edf0f4');
check(inventoryRows($page)[123]['image']==='https://community.akamai.steamstatic.com/economy/image/abc_123/128fx128f');
check(inventoryRows(['success'=>1,'total_inventory_count'=>0])===[]);
fails(static function(){inventoryRows(['success'=>1]);});
check(inventoryRows(array_replace($page,['descriptions'=>[array_replace($d,['tradable'=>0])]]))===[]);
check(inventoryRows(array_replace($page,['descriptions'=>[array_replace($d,['icon_url'=>'https://evil.test'])]]))[123]['image']==='');
$fetch=static function($url)use($page,$id){check($url==='https://steamcommunity.com/inventory/'.$id.'/440/2?l=koreana&count=1000');return json_encode($page);};
fails(static function(){steamRequest('https://steamcommunity.com/openid/login.evil');});
check(count(fetchBackpack($id,$fetch))===1);
fails(static function()use($fetch){fetchBackpack('../admin',$fetch);});
fails(static function()use($id){fetchBackpack($id,static function(){return '{"success":0}';});});
$n=0;
$pages=static function($url)use(&$n,$page){$n++;if($n===1)return json_encode($page+['more_items'=>1,'last_assetid'=>'123']);check(strpos($url,'start_assetid=123')!==false);$second=$page;$second['assets'][0]['assetid']='456';return json_encode($second);};
check(count(fetchBackpack($id,$pages))===2&&$n===2);
fails(static function()use($id,$page){fetchBackpack($id,static function()use($page){return json_encode($page+['more_items'=>1,'last_assetid'=>'123']);});});
echo "PASS OpenID signature verification invocation, identity/state/nonce/signed-field guards; inventory owner URL, tradability, pagination, duplicates and icon sanitization\n";
