<?php
require __DIR__.'/market.php';
require __DIR__.'/market_view.php';
function check($v){if(!$v)throw new RuntimeException('Market assertion failed');}
$prices=['Hat'=>['defindex'=>[123],'prices'=>[5=>['Tradable'=>['Craftable'=>[13=>['value'=>10,'value_high'=>12,'currency'=>'keys','last_update'=>100]]]]]],'Mann Co. Supply Crate Key'=>['defindex'=>[5021],'prices'=>[6=>['Tradable'=>['Craftable'=>[['value'=>60,'currency'=>'metal']]]]]]];
$effects=[['id'=>13,'en'=>'Burning Flames','ko'=>'타오르는 불꽃']];
$row=['en'=>'Unusual Hat','details'=>[['text'=>'★ 범상찮은 효과: 타오르는 불꽃']]];
$id=marketIdentity($row,$prices,$effects);check($id['sku']==='Burning Flames Hat'&&$id['effect']===13);
check(marketIdentity(['en'=>'Unusual Hat','details'=>[]],$prices,$effects)===null);
check(marketIdentity(['en'=>'Strange Unusual Hat'],$prices,$effects)===null);
check(marketIdentity(['en'=>'Professional Killstreak Hat'],$prices,$effects)===null);
check(marketLink(['en'=>'Unusual Taunt: Burstchester','details'=>[['text'=>'★ 범상찮은 효과: 밀밭']]])==='https://backpack.tf/stats/Unusual/Taunt%3A%20Burstchester/Tradable/Craftable/3224');
check(marketLink(['en'=>'Mann Co. Supply Crate Key'])==='https://backpack.tf/stats/Unique/Mann%20Co.%20Supply%20Crate%20Key/Tradable/Craftable');
check(marketLink(['en'=>'Unknown Variant','assetid'=>'123'])==='https://backpack.tf/stats/Unique/Unknown%20Variant/Tradable/Craftable');
check(marketLink(['en'=>'Strange Australium Flame Thrower','assetid'=>'123'])==='https://backpack.tf/stats/Strange/Australium%20Flame%20Thrower/Tradable/Craftable');
check(marketLink(['en'=>'Strange Australium Flame Thrower','details'=>[['text'=>'Not Usable in Crafting']]])==='https://backpack.tf/stats/Strange/Australium%20Flame%20Thrower/Tradable/Non-Craftable');
check(marketIdentity(['en'=>'Strange Australium Flame Thrower'],$prices,$effects)===null);
$icon=marketIcon(['en'=>'Mann Co. Supply Crate Key']);check(strpos($icon,'data-market-url=')!==false);check(strpos($icon,'<button type="button"')!==false);check(strpos($icon,'href=')===false);check(strpos($icon,'target=')===false);
$non=$row;$non['details'][]=['text'=>'( 제작에 사용할 수 없음 )'];check(marketIdentity($non,$prices,$effects)['craft']===false);
$item=['defindex'=>123,'quality'=>5,'attributes'=>[['defindex'=>134,'float_value'=>13]]];
$sell=['item'=>$item,'intent'=>'sell','currencies'=>['keys'=>10,'metal'=>1]];
$buy=['item'=>$item,'intent'=>'buy','currencies'=>['keys'=>9]];
$wrong=$sell;$wrong['item']['attributes'][0]['float_value']=14;$wrong['currencies']=['metal'=>1];
$wrongQuality=$sell;$wrongQuality['item']['quality']=6;$wrongQuality['currencies']=['metal'=>1];
$invalid=$sell;$invalid['currencies']=['keys'=>-1];
$out=marketQuote($id,$prices,['listings'=>[$sell,$buy,$wrong,$wrongQuality,$invalid]],200);
check($out['suggested']==='10–12 키'&&$out['sell']==='10키 + 1정'&&$out['buy']==='9키'&&$out['price_updated']===100);
check(marketAmount(['value'=>-1,'currency'=>'keys'])===null);
$dir=sys_get_temp_dir().'/market-test-'.bin2hex(random_bytes(6));mkdir($dir);mkdir($dir.'/users');
try{
 marketSave($dir.'/users/market-config.json',['apiKey'=>str_repeat('a',24),'accessToken'=>'secret']);
 $calls=0;$fetch=static function($kind,$sku='')use(&$calls,$prices,$sell){$calls++;return $kind==='prices'?['response'=>['success'=>1,'items'=>$prices]]:['appid'=>440,'sku'=>$sku,'listings'=>[$sell]];};
 $a=marketFetch($dir,$row,$fetch);$b=marketFetch($dir,$row,$fetch);
 check($a===$b&&$calls===2&&$a['sell']==='10키 + 1정');
 check((fileperms($dir.'/users/market-prices.json')&0777)===0600);
 check(strpos(json_encode($a),'secret')===false);
}finally{foreach(glob($dir.'/users/*') as $file)unlink($file);rmdir($dir.'/users');rmdir($dir);}
echo "PASS exact quality/effect, variant refusal, currency ordering, negative rejection, private cache and secret exclusion\n";
