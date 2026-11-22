<?php
declare(strict_types=1);
require __DIR__.'/catalog.php';
require __DIR__.'/seller.php';
require __DIR__.'/steam.php';
require __DIR__.'/settings.php';
require __DIR__.'/listings.php';
require __DIR__.'/checkout.php';
require __DIR__.'/returns.php';
require __DIR__.'/market_view.php';
require __DIR__.'/finance.php';
ini_set('display_errors','0');
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'self'; img-src 'self' https://community.akamai.steamstatic.com https://community.cloudflare.steamstatic.com https://steamcommunity-a.akamaihd.net; form-action 'self' https://steamcommunity.com; base-uri 'none'; frame-ancestors 'self'");
$dir = getenv('BOTSHOP_DATA_DIR') ?: dirname(__DIR__,2).'/.bot-trade-shop-private';
require __DIR__.'/game-session.php';
shopSessionStart();
if (!isset($_SESSION['csrf'])) $_SESSION['csrf']=bin2hex(random_bytes(24));
unset($_SESSION['admin_until']);
if(isset($_GET['admin'])&&($_SERVER['REQUEST_METHOD']??'GET')==='GET'){header('Location: ?tab=sell',true,303);exit;}
$draft=['keys'=>'0','refined'=>'0'];
$preview=null;
$source='backpack';
$steamid=steamUser();
if(!$steamid)unset($_SESSION['backpack']);
$error=''; $notice=''; $toast=''; $rows=[];$tradeURL='';$myListings=[];$intakeReady=false;$purchaseReady=false;$returnReady=false;$orders=[];
function esc($s): string {return htmlspecialchars((string)$s,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');}
try {
    if (($_SERVER['REQUEST_METHOD']??'GET')==='POST') {
        if ((int)($_SERVER['CONTENT_LENGTH']??0)>8192) throw new InvalidArgumentException('요청이 너무 큽니다.');
        if (!is_string($_POST['csrf']??null) || !hash_equals($_SESSION['csrf'],$_POST['csrf'])) {http_response_code(403);throw new InvalidArgumentException('페이지를 새로 열고 다시 시도하세요.');}
        $action=field($_POST,'action',16);
        // Publication is restricted to the bot's authenticated receipt verification.
        if(!in_array($action,['backpack_load','backpack_preview','save_trade_url','register_item','purchase','listing_hide','listing_show','return_item','claim_payout','finance'],true)){http_response_code(403);throw new InvalidArgumentException('내 백팩에서 아이템을 선택하세요. 봇 입고 확인 전에는 상품을 공개할 수 없습니다.');}
        if($action==='finance'){
            if(!$steamid)throw new InvalidArgumentException('게임에서 상점을 다시 열어 주세요.');
            $nonce=field($_POST,'nonce',32);
            if(!hash_equals($_SESSION['finance_nonce']??'', $nonce)||$nonce==='')throw new InvalidArgumentException('이미 요청했거나 만료되었습니다. 페이지를 새로 열어 주세요.');
            $kind=field($_POST,'kind',16);
            if(in_array($kind,['play_adjust','adjust','withdraw'],true))financeWallet($dir,$steamid,$kind,$_POST);
            else financeCreate($dir,$steamid,$kind,$_POST);
            unset($_SESSION['finance_nonce']);$notice='요청을 장부에 기록했습니다. 아래 진행 상태를 확인하세요.';
        }
        if(in_array($action,['listing_hide','listing_show'],true)){
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('Steam 로그인이 필요합니다.');}
            listingVisibility($dir,field($_POST,'listing',32),$steamid,$action==='listing_hide');
            $notice=$action==='listing_hide'?'판매를 중지했습니다. 아이템은 봇에 보관됩니다.':'상품을 다시 판매합니다.';
        }
        if($action==='return_item'){
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('Steam 로그인이 필요합니다.');}
            returnCreate($dir,field($_POST,'listing',32),$steamid);
            $notice='반환을 요청했습니다. 내 상품에서 거래제안을 확인한 뒤 Steam에서 수락하세요.';
        }
        if($action==='claim_payout'){
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('Steam 로그인이 필요합니다.');}
            $claim=purchaseClaim($dir,field($_POST,'listing',32),field($_POST,'order',32),$steamid);
            $notice=$claim['status']==='settled'?'이미 판매대금을 수령했습니다.':($claim['status']==='settling'?'이미 판매대금 거래제안을 보냈습니다. 기존 제안을 확인하세요.':'판매대금 수령을 요청했습니다. 내 상품에서 거래제안을 확인하고 Steam에서 수락하세요.');
        }
        if($action==='purchase'){
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('Steam 로그인 후 구매해 주세요.');}
            purchaseCreate($dir,field($_POST,'listing',32),$steamid);
            $notice='구매 요청을 등록했습니다. 내 상품 탭의 거래 진행 상태에서 Steam 거래제안을 확인하세요.';
        }
        if($action==='register_item'){
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('Steam 로그인이 필요합니다.');}
            $pending=$_SESSION['listing_preview']??[];
            if(($pending['owner']??'')!==$steamid||time()-($pending['time']??0)>300||!hash_equals($pending['nonce']??'',field($_POST,'confirmation',48)))throw new InvalidArgumentException('아이템과 가격을 다시 확인하세요.');
            listingCreate($dir,$steamid,$pending['item'],$pending['price']);
            $notice='입고 요청을 등록했습니다. 내 상품 탭에서 거래제안을 확인하고 Steam에서 수락해 주세요.';
        }
        if($action==='save_trade_url'){
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('Steam 로그인 후 거래 URL을 설정하세요.');}
            saveTradeURL($dir,$steamid,field($_POST,'trade_url',180));$notice='본인의 거래 URL을 저장했습니다.';
        }
        if($action==='backpack_load'||$action==='backpack_preview') {
            $source='backpack';
            if(!$steamid){http_response_code(403);throw new InvalidArgumentException('내 백팩은 Steam 로그인 후 사용할 수 있습니다.');}
            if($action==='backpack_load') {
                if(time()-($_SESSION['backpack_attempt']??0)<30)throw new InvalidArgumentException('백팩 새로고침은 30초 간격으로 가능합니다.');
                $_SESSION['backpack_attempt']=time();unset($_SESSION['backpack']);
                try {$items=fetchBackpack($steamid,static function($url){return steamRequest($url);});}
                catch(Throwable $e){throw new InvalidArgumentException($e instanceof JsonException?'Steam 백팩 응답을 해석하지 못했습니다. 다시 시도하세요.':$e->getMessage());}
                $_SESSION['backpack']=['owner'=>$steamid,'time'=>time(),'items'=>$items];
                $notice='백팩을 불러왔습니다. 거래 가능한 아이템만 표시합니다.';
            } else {
                $asset=field($_POST,'assetid',20);$cache=$_SESSION['backpack']??[];
                if(($cache['owner']??'')!==$steamid||time()-($cache['time']??0)>300)throw new InvalidArgumentException('백팩을 다시 불러온 뒤 선택하세요.');
                $item=$cache['items'][$asset]??null;
                if(!$item)throw new InvalidArgumentException('본인의 백팩 목록에서 아이템을 선택하세요.');
                $draft['keys']=field($_POST,'keys',6);$draft['refined']=field($_POST,'refined',9);
                $price=sellerPrice($draft);$draft['refined']=$price['refined'];
                $preview=['item'=>$item,'price'=>$price];
                $_SESSION['listing_preview']=$preview+['owner'=>$steamid,'time'=>time(),'nonce'=>bin2hex(random_bytes(24))];
            }
        }
    }
    if($steamid)$tradeURL=readTradeURL($dir,$steamid);
    $intakeReady=shopReady($dir);$purchaseReady=checkoutReady($dir);$returnReady=returnReady($dir);
    foreach(listingRead($dir) as $listing){
        if($steamid&&$listing['owner']===$steamid)$myListings[]=$listing;
        $available=true;
        foreach($listing['orders']??[] as $order){
            if($order['status']!=='failed')$available=false;
            if($steamid&&in_array($steamid,[$order['buyer'],$order['seller']],true))$orders[]=$order+['name'=>$listing['item']['ko']];
        }
        if($listing['status']==='published'&&$available&&empty($listing['hidden'])&&!listingHasReturn($listing))$rows[]=['code'=>$listing['code'],'owner'=>$listing['owner'],'name'=>$listing['item']['ko'],'market'=>$listing['item']['en'],'image'=>$listing['item']['image'],'price'=>$listing['price'],'buy_enabled'=>true,'item'=>$listing['item']];
    }
} catch (PurchaseFundsException $e) {$toast=$e->getMessage();}
catch (InvalidArgumentException $e) {$error=$e->getMessage();}
catch (TradeSettingsException $e) {http_response_code(503);$error='거래 URL 설정 저장소에 접근할 수 없습니다. 관리자에게 문의해 주세요. 백팩 검색 오류가 아닙니다.';error_log('Bot shop trade settings storage unavailable');}
catch (Throwable $e) {http_response_code(503);$error='상품 검색 목록 또는 저장소를 불러올 수 없습니다. 상품이 없는 것이 아니므로 잠시 후 다시 시도하세요.';error_log('Bot shop catalog/search failure');}
$tab=in_array($_GET['tab']??'', ['sell','settings','my','points','treasury'],true)?$_GET['tab']:'buy';
$query=is_string($_GET['q']??null)?substr($_GET['q'],0,120):'';
$shown=array_filter($rows,static function($r) use($tab,$query){return !empty($r[$tab.'_enabled']) && ($query==='' || stripos($r['name'].' '.$r['market'],$query)!==false);});
?>
<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>봇거래 · 교역소</title><link rel="stylesheet" href="shop.css?v=20261031-market-link-copy"><script src="game-frame.js?v=1" defer></script><script src="backpack.js?v=20261031-game-session" defer></script><script src="market.js?v=20261031-game-session" defer></script></head><body>
<?php if($toast):?><div class="purchase-toast" role="alert"><?=esc($toast)?></div><?php endif;?>
<div class="shell"><header><div class="brand">B<span>↔</span>T <small>TF2 TRADING POST</small></div></header>
<section class="hero"><div class="eyebrow">당신의 다음 아이템을 만나보세요</div><h1>봇거래 <span>교역소</span></h1><p>상품을 둘러보고 판매할 아이템을 등록하세요.</p><div class="status"><?=$intakeReady?'● 판매 입고 봇 연결됨':'● 판매 입고 봇 연결 대기'?></div></section>
<?php if($error):?><p class="error" role="alert"><?=esc($error)?></p><?php endif;?>
<?php if($notice):?><p class="success" role="status"><?=esc($notice)?></p><?php endif;?>
<nav aria-label="거래 방향"><a class="<?=$tab==='buy'?'active':''?>" href="?tab=buy">구매 <small>등록 상품 보기</small></a><a class="<?=$tab==='sell'?'active':''?>" href="?tab=sell">판매 <small>판매물품 등록하기</small></a><a class="<?=$tab==='my'?'active':''?>" href="?tab=my">내 상품</a><a class="<?=$tab==='settings'?'active':''?>" href="?tab=settings">설정</a><a class="<?=$tab==='points'?'active':''?>" href="?tab=points">게임 포인트</a><?php if($steamid===FINANCE_OWNER):?><a class="<?=$tab==='treasury'?'active':''?>" href="?tab=treasury">소유자 자금 관리</a><?php endif;?></nav>
<?php if(in_array($tab,['points','treasury'],true)): require __DIR__.'/finance_view.php'; elseif($tab==='my'): require __DIR__.'/my_listings.php'; elseif($tab==='settings'): require __DIR__.'/settings_view.php'; elseif($tab==='sell'):?>
<section class="panel"><h2>판매물품 등록하기</h2><p class="muted">① 본인 확인 · 내 백팩에서 선택 → ② 가격 입력 및 봇에 아이템 전달 → ③ 실제 입고 완료 후 상점 공개</p>
<?php if($steamid&&$tradeURL===''):?><p class="warning">판매 입고 전에 본인의 거래 URL을 등록해 주세요. <a href="?tab=settings">설정에서 거래 URL 등록하기 →</a></p><?php endif;?>
<?php require __DIR__.'/backpack_view.php'; ?>
<?php if($preview)require __DIR__.'/confirmation.php'; ?>
<p class="muted">입고는 판매 완료가 아니라 보관입니다. 실제 수령 후 상품이 공개됩니다. 판매 완료 후 내 상품에서 판매대금 받기를 누르면 전액을 Steam 거래제안으로 지급합니다. 1키 또는 64정 이상 정산은 주인 승인 후 진행됩니다. 판매 중지는 내 상품 탭에서 할 수 있습니다. 아이템 돌려받기도 내 상품 탭에서 요청할 수 있습니다.</p>
</section>
<?php else:?>
<div class="toolbar"><h2><?=$tab==='buy'?'구매 가능한 상품':'봇이 매입할 상품'?> <span><?=count($shown)?></span></h2><form method="get"><input type="hidden" name="tab" value="<?=$tab?>"><label class="search">상품 검색<input name="q" value="<?=esc($query)?>" maxlength="120" placeholder="상품명으로 찾기"></label><button class="secondary" type="submit">검색</button></form></div>
<main class="grid"><?php foreach($shown as $row):?><article class="card"><div class="art"><?=marketIcon($row['item'])?><?php if($row['image']):?><img src="<?=esc($row['image'])?>" alt="<?=esc($row['name'])?>"><?php else:?><span class="placeholder">TF<span>2</span></span><?php endif;?></div><div class="details"><span class="tag">입고 확인 · 등록 상품</span><h3><?=esc($row['name'])?></h3><p class="market"><?=esc($row['market'])?></p><div class="price"><?=esc(sellerPriceText($row['price']))?></div><p class="muted">보관 중인 아이템 1개</p><?php if(!$steamid):?><p>게임에서 !봇거래를 열어 구매하세요.</p><?php elseif($row['owner']===$steamid):?><button disabled>내 판매 상품</button><?php elseif($tradeURL===''):?><a href="?tab=settings">거래 URL 등록 후 구매</a><?php else:?><form method="post" action="?tab=buy"><input type="hidden" name="csrf" value="<?=esc($_SESSION['csrf'])?>"><input type="hidden" name="listing" value="<?=esc($row['code'])?>"><button name="action" value="purchase" <?=$purchaseReady?'':'disabled'?>><?=$purchaseReady?'이 가격으로 구매 거래제안 요청':'구매 봇 연결 대기'?></button></form><?php endif;?></div></article><?php endforeach;?></main>
<?php if(!$shown):?><section class="empty"><div>＋</div><h2><?=$query!==''?'검색 결과가 없습니다':'아직 등록된 상품이 없습니다'?></h2><p>판매자의 아이템 입고가 확인되면 이곳에 공개됩니다.</p><a href="?tab=sell">상품 등록 페이지 →</a></section><?php endif;?>
<?php endif;?>
<?php if($tab==='my'){require __DIR__.'/orders_view.php';require __DIR__.'/completed_view.php';} ?>
<footer id="trade-state">구매는 상품과 키·금속을 한 거래제안에서 직접 교환합니다. 정확한 금액의 키·금속을 준비하세요. 거스름돈은 제공하지 않습니다.<br>판매자는 거래 완료 후 내 상품에서 판매대금 받기를 요청할 수 있습니다. 수수료는 없습니다. 금속 충전과 포인트 출금은 기존 메뉴를 이용하세요.</footer></div><div id="market-tip" role="tooltip" hidden></div><div id="market-link-overlay" hidden><section class="market-link-modal" role="dialog" aria-modal="true" aria-labelledby="market-link-title"><h2 id="market-link-title">backpack.tf 아이템 주소</h2><p>주소를 복사해서 Chrome이나 Edge에서 열어 주세요.</p><label>아이템 페이지 주소<input id="market-link-url" type="text" readonly spellcheck="false"></label><p id="market-link-status" role="status"></p><button id="market-link-copy" type="button">주소 복사</button> <button id="market-link-close" type="button" class="secondary">닫기</button></section></div></body></html>
