"""Disposable loopback PHP container; no bot, Steam or live ledger access."""
import http.client
import re
import subprocess
import time
import uuid
import hashlib
import secrets
import json
from pathlib import Path
from urllib.parse import urlencode

name='botshop-test-'+uuid.uuid4().hex[:10]
folder=Path(__file__).resolve().parent
def docker(*args):
    return subprocess.check_output(['docker',*args],text=True).strip()

try:
    docker('run','--rm','-d','--name',name,'-p','127.0.0.1::8080',
           '--mount',f'type=bind,source={folder},target=/app,readonly',
           '-e','BOTSHOP_DATA_DIR=/tmp/botshop-test','-e','BOTSHOP_GAME_DIR=/tmp/game-grants','-e','BOTSHOP_WALLET_DIR=/tmp/wallet-fixture','php:8.3-cli','sh','-c',
           'cp -r /app /tmp/shop-app && php /tmp/shop-app/test_setup.php && php -S 0.0.0.0:8080 -t /tmp/shop-app')
    port=int(docker('port',name,'8080/tcp').rsplit(':',1)[1])
    # Inventory fixture is injected only into the disposable copy, never production PHP.
    inventory_fixture="""$p='/tmp/shop-app/steam.php'; $s=file_get_contents($p); $s=str_replace('function fetchBackpack(', 'function originalFetchBackpack(', $s); $s.='\nfunction fetchBackpack(string $id,callable $fetch): array { return $_SESSION["fixture_payment"] ?? array_merge(array_fill(0,20,["en"=>"Mann Co. Supply Crate Key"]),array_fill(0,20,["en"=>"Refined Metal"]),array_fill(0,20,["en"=>"Reclaimed Metal"]),array_fill(0,20,["en"=>"Scrap Metal"])); }'; file_put_contents($p,$s);"""
    docker('exec',name,'php','-r',inventory_fixture)
    docker('exec',name,'php','-r',"session_name('botshop');session_id('legacy-session-must-not-authenticate');session_start();$_SESSION['steamid']='76561199077147589';$_SESSION['steam_until']=time()+3600;session_write_close();")
    cookie='botshop=legacy-session-must-not-authenticate'
    game_token='';game_id='';last_grant=0
    def refresh_grant():
        global last_grant
        if game_token and time.time()-last_grant>5:
            script="@mkdir('/tmp/game-grants',0700);file_put_contents('/tmp/game-grants/'.$argv[1].'.json',json_encode(['steamid'=>$argv[2],'opened'=>time(),'expires'=>time()+15]));"
            docker('exec',name,'php','-r',script,game_token,game_id);last_grant=time.time()
    def authenticate(identity):
        global game_token,game_id,last_grant
        game_token=secrets.token_hex(32);game_id=identity;last_grant=0;refresh_grant()
        return hashlib.sha256(('botshop-game:'+game_token).encode()).hexdigest()

    def request(path='/',body=None):
        global cookie
        c=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
        refresh_grant()
        headers={'Cookie':cookie}
        if game_token:headers['X-Botshop-Session']=game_token
        if body is not None:headers['Content-Type']='application/x-www-form-urlencoded'
        c.request('POST' if body is not None else 'GET',path,urlencode(body) if body is not None else None,headers)
        r=c.getresponse();text=r.read().decode();status=r.status
        for k,v in r.getheaders():
            if k.lower()=='set-cookie':
                raise AssertionError('Shop endpoints must not set authentication cookies')
        c.close();return status,text
    for attempt in range(40):
        try:status,body=request('/?admin=1');break
        except OSError:time.sleep(.25)
    assert status==303
    status,body=request('/?tab=sell')
    assert status==200 and '판매물품 등록하기' in body and 'type="password"' not in body
    csrf='0'*48
    assert request('/?tab=sell',{'action':'preview','csrf':'wrong'})[0]==403
    for action in ['login','register','publish','search','preview']:
        assert request('/?tab=sell',{'action':action,'csrf':csrf})[0]==403
    assert 'name="reclaimed"' not in body and 'name="scrap"' not in body
    assert '!봇거래' in body and '상품명 검색' not in body and 'name="name"' not in body
    assert request('/?tab=settings',{'action':'save_trade_url','csrf':csrf,'trade_url':'https://example.com'})[0]==403
    assert '설정 · 내 거래 URL' in request('/?tab=settings')[1]
    assert '아직 등록된 상품이 없습니다' in request('/')[1]
    assert 'type="password"' not in request('/')[1]
    status,body=request('/?tab=sell&source=backpack')
    assert status==200 and '!봇거래' in body and '아이템 ID' not in body
    assert request('/?tab=sell&source=backpack',{'action':'backpack_load','csrf':csrf})[0]==403
    assert request('/?tab=sell&source=backpack',{'action':'backpack_preview','csrf':csrf,'assetid':'123'})[0]==403
    assert request('/auth.php?state=forged&openid.mode=id_res')[0]==403
    assert request('/auth.php',{'action':'login','csrf':'wrong'})[0]==403
    status,body=request('/auth.php',{'action':'login','csrf':csrf})
    assert status==403
    # Create an authenticated fixture session in the disposable container, never a web backdoor.
    sid=authenticate('76561199077147589')
    seller_token=game_token; seller_sid=sid
    status,body=request('/?tab=sell')
    csrf=re.search(r'name="csrf" value="([a-f0-9]+)"',body)[1]
    fixture="session_name('botshop_game'); session_id($argv[1]); session_start(); $_SESSION['steamid']='76561199077147589'; $_SESSION['steam_until']=time()+3600; $_SESSION['backpack']=['owner'=>'76561199077147589','time'=>time(),'items'=>['123'=>['assetid'=>'123','ko'=>'Fixture Token','en'=>'Fixture Token','image'=>'https://community.akamai.steamstatic.com/economy/image/fixture/128fx128f']]]; session_write_close();"
    docker('exec',name,'php','-r',fixture,sid)
    url='https://steamcommunity.com/tradeoffer/new/?partner=1116881861&token=Abc_123-'
    setting={'action':'save_trade_url','csrf':csrf,'trade_url':url}
    assert 'URL이 등록되지 않았습니다' in request('/?tab=settings')[1]
    assert request('/?tab=settings',dict(setting,csrf='bad'))[0]==403
    for bad in [url.replace('1116881861','1116881862'),url+'&evil=1',url.replace('https:','http:'),url.replace('steamcommunity.com','steamcommunity.com.evil.test')]:
        assert '본인 계정의 Steam 거래 URL' in request('/?tab=settings',dict(setting,trade_url=bad))[1]
    status,body=request('/?tab=settings',setting)
    assert status==200 and '본인의 거래 URL을 저장했습니다' in body and 'Abc_123-' not in body
    assert '거래 URL이 등록되어 있습니다' in request('/?tab=settings')[1]
    assert '키·금속 직접 거래 방식입니다.' not in body
    docker('exec',name,'mv','/tmp/botshop-test/users','/tmp/botshop-test/users.saved')
    status,body=request('/?tab=settings')
    assert status==503 and '거래 URL 설정 저장소에 접근할 수 없습니다' in body
    docker('exec',name,'mv','/tmp/botshop-test/users.saved','/tmp/botshop-test/users')
    assert request('/?tab=settings')[0]==200
    assert docker('exec',name,'stat','-c','%a','/tmp/botshop-test/users/trade-url-76561199077147589.txt')=='600'
    status,body=request('/?tab=sell&source=backpack')
    assert status==200 and 'value="123"' in body
    assert '이름 일부 입력:' not in body and '번째 표시' not in body and '거래 가능한 검색 결과' not in body
    assert '검색 지우기 · 전체 보기' not in body
    assert body.index('name="keys"') < body.index('value="backpack_preview"') < body.index('<fieldset class="backpack-grid"')
    assert '<small>ID ' not in body and 'role="tooltip"' in body
    assert 'backpack.js?v=20261031-game-session' in body
    assert 'market.js?v=20261031-game-session' in body and 'aria-label="backpack.tf 시세 보기"' in body
    market_ref=re.search(r'data-market-ref="([a-f0-9]{64})"',body)[1]
    assert request('/market-api.php?ref=forged')[0]==400
    cache_fixture="require '/tmp/shop-app/market.php'; session_name('botshop_game'); session_id($argv[1]); session_start(); $ref=$argv[2]; $r=$_SESSION['market_items'][$ref]; $h=hash('sha256',json_encode([$r['en'],$r['details']])); marketSave('/tmp/botshop-test/users/market-'.substr($h,0,2).'.json',['key'=>$h,'until'=>time()+300,'quote'=>['suggested'=>'1 키','sell'=>'2키','buy'=>'1키','checked'=>time(),'orders_ok'=>true]]);"
    docker('exec',name,'php','-r',cache_fixture,sid,market_ref)
    status,quote=request('/market-api.php?ref='+market_ref)
    assert status==200 and 'suggested' in quote and 'apiKey' not in quote and 'accessToken' not in quote
    rich="session_name('botshop_game'); session_id($argv[1]); session_start(); $_SESSION['backpack']['items']['123']+=['color'=>'8650ac','type'=>'Level 10 Hat','tags'=>[['text'=>'Assassin','color'=>'d32ce6']],'details'=>[['text'=>'Paint: Pink <img src=x onerror=alert(1)>','color'=>'ffd700']]]; session_write_close();"
    docker('exec',name,'php','-r',rich,sid)
    status,body=request('/?tab=sell&source=backpack')
    assert 'data-color="8650ac"' in body and 'data-color="d32ce6"' in body
    assert 'Level 10 Hat' in body and 'Paint: Pink &lt;img' in body and '<img src=x' not in body
    bp={'action':'backpack_preview','csrf':csrf,'assetid':'123','keys':'0','refined':'1.99'}
    assert 'src="https://community.akamai.steamstatic.com/economy/image/fixture/128fx128f"' in body
    status,body=request('/?tab=sell&source=backpack',bp)
    assert status==200 and 'Fixture Token' in body and '2정' in body and '0키 +' not in body
    assert 'role="dialog"' in body and '이 아이템을 등록하시겠습니까?' in body
    confirmation=re.search(r'name="confirmation" value="([a-f0-9]+)"',body)[1]
    registration={'action':'register_item','csrf':csrf,'confirmation':confirmation,'assetid':'999','keys':'999'}
    assert '입고 봇이 연결되지 않았습니다' in request('/?tab=sell',registration)[1]
    docker('exec',name,'php','-r',"file_put_contents('/tmp/botshop-test/users/shop-heartbeat',(string)time());")
    assert request('/?tab=sell',dict(registration,csrf='bad'))[0]==403
    assert '아이템과 가격을 다시 확인하세요' in request('/?tab=sell',dict(registration,confirmation='bad'))[1]
    for _ in range(2):
        assert '입고 요청을 등록했습니다' in request('/?tab=sell',registration)[1]
    verify="require '/tmp/shop-app/settings.php'; require '/tmp/shop-app/listings.php'; $d='/tmp/botshop-test'; $r=listingRead($d); if(count($r)!==1)exit(1); $r=array_values($r)[0]; if($r['asset']!=='123'||$r['price']['keys']!=0||$r['price']['refined']!=2)exit(2); listingUpdate($d,['code'=>$r['code'],'owner'=>$r['owner'],'asset'=>$r['asset'],'offer'=>'100','status'=>'published','trade'=>'200','bot_asset'=>'300']);"
    assert '아직 등록된 상품이 없습니다' in request('/')[1]
    docker('exec',name,'php','-r',verify)
    assert 'Fixture Token' in request('/')[1]
    assert '개수는' in request('/?tab=sell',dict(bp,keys='-1'))[1]
    assert '0보다 커야' in request('/?tab=sell',dict(bp,refined='0'))[1]
    assert '소수부는' in request('/?tab=sell',dict(bp,refined='1.12'))[1]
    assert '1정제 + 1재활용 + 2폐기' in request('/?tab=sell',dict(bp,refined='1.55'))[1]
    assert '본인의 백팩 목록' in request('/?tab=sell&source=backpack',dict(bp,assetid='999'))[1]
    many="session_name('botshop_game'); session_id($argv[1]); session_start(); $item=$_SESSION['backpack']['items']['123']; $_SESSION['backpack']['items']=[]; for($i=1;$i<=205;$i++){ $item['assetid']=(string)$i; $_SESSION['backpack']['items'][(string)$i]=$item; } session_write_close();"
    docker('exec',name,'php','-r',many,sid)
    base='/?tab=sell&source=backpack'
    for query,count,current,first,last in [('',50,1,1,50),('&page=2',50,2,51,100),('&page=3',50,3,101,150),('&page=5',5,5,201,205),('&page=999',5,5,201,205),('&page=-2',50,1,1,50),('&page[]=2',50,1,1,50)]:
        status,body=request(base+query)
        assert status==200 and body.count('name="assetid"')==count
        assert f'현재 {current} / 전체 5페이지' in body
        assert f'name="assetid" value="{first}"' in body and f'name="assetid" value="{last}"' in body
        assert 'class="backpack-grid"' in body and '바로 이동' in body
    status,body=request(base+'&page=2&bpq=Fixture')
    assert 'name="bpq" value="Fixture"' in body and 'bpq=Fixture&amp;page=3#backpack-start' in body
    assert 'id="backpack-start"' in body and 'method="get" action="#backpack-start"' in body
    status,body=request(base+'&page=2&bpq=Missing')
    assert '현재 1 / 전체 1페이지' in body and 'name="assetid"' not in body
    status,body=request(base+'&page=5',dict(bp,assetid='205'))
    assert status==200 and '2정' in body and '0키 +' not in body and '현재 5 / 전체 5페이지' in body
    korean="session_name('botshop_game'); session_id($argv[1]); session_start(); $_SESSION['backpack']['items']['1']['ko']='범상찮은 모자'; $_SESSION['backpack']['items']['2']['ko']='정제 금속'; $_SESSION['backpack']['items']['3']['ko']='정찰 모자'; session_write_close();"
    docker('exec',name,'php','-r',korean,sid)
    for term,expected in [('범상찮은',[1]),('정',[2,3]),('정제금속',[2])]:
        status,body=request('/?'+urlencode({'tab':'sell','bpq':term}))
        assert status==200 and body.count('name="assetid"')==len(expected)
        for asset in expected: assert f'name="assetid" value="{asset}"' in body
    status,body=request('/?'+urlencode({'tab':'sell','bpq':'<script>alert(1)</script>'}))
    assert '&lt;script&gt;' in body and '<script>alert(1)</script>' not in body
    assert request('/?tab=sell')[1].count('name="assetid"')==50
    listing=docker('exec',name,'php','-r',"$r=json_decode(file_get_contents('/tmp/botshop-test/users/listings.json'),true); echo array_key_first($r);")
    docker('exec',name,'php','-r',"file_put_contents('/tmp/botshop-test/users/checkout-heartbeat',(string)time());")
    buy={'action':'purchase','csrf':csrf,'listing':listing}
    assert '본인의 상품은 구매할 수 없습니다' in request('/?tab=buy',buy)[1]
    assert '내 입고 진행 상태' not in request('/?tab=sell')[1]
    assert 'value="listing_hide"' in request('/?tab=my')[1]
    visibility={'action':'listing_hide','csrf':csrf,'listing':listing}
    assert request('/?tab=my',dict(visibility,csrf='bad'))[0]==403
    assert '판매를 중지했습니다' in request('/?tab=my',visibility)[1]
    assert 'Fixture Token' not in request('/?tab=buy')[1]
    assert 'value="listing_show"' in request('/?tab=my')[1]
    assert '상품을 다시 판매합니다' in request('/?tab=my',dict(visibility,action='listing_show'))[1]
    returning={'action':'return_item','csrf':csrf,'listing':listing}
    assert '반환 봇 연결을 기다리고 있습니다' in request('/?tab=my',returning)[1]
    docker('exec',name,'php','-r',"file_put_contents('/tmp/botshop-test/users/return-heartbeat',(string)time());")
    assert request('/?tab=my',dict(returning,csrf='bad'))[0]==403
    for _ in range(2):assert '반환을 요청했습니다' in request('/?tab=my',returning)[1]
    assert '반환 거래제안 준비 중' in request('/?tab=my')[1]
    assert 'value="listing_show"' not in request('/?tab=my')[1]
    assert 'Fixture Token' not in request('/?tab=buy')[1]
    cancel_return="require '/tmp/shop-app/settings.php'; require '/tmp/shop-app/listings.php'; require '/tmp/shop-app/returns.php'; $d='/tmp/botshop-test'; $rows=listingRead($d); $l=array_key_first($rows); $r=$rows[$l]['returns']; if(count($r)!==1)exit(1); $b=['listing'=>$l,'code'=>array_key_first($r)]; returnUpdate($d,$b+['status'=>'sent','offer'=>'888']); returnUpdate($d,$b+['status'=>'failed']);"
    docker('exec',name,'php','-r',cancel_return)
    assert '아이템 돌려받기' in request('/?tab=my')[1]
    assert '상품을 다시 판매합니다' in request('/?tab=my',dict(visibility,action='listing_show'))[1]
    sid=authenticate('76561198038759714')
    docker('exec',name,'php','-r',"session_name('botshop_game');session_id($argv[1]);session_start();$_SESSION['csrf']=$argv[2];session_write_close();",sid,csrf)
    buyer="session_name('botshop_game'); session_id($argv[1]); session_start(); $_SESSION['steamid']='76561198038759714'; session_write_close();"
    docker('exec',name,'php','-r',buyer,sid)
    assert '본인의 상품만 변경할 수 있습니다' in request('/?tab=my',visibility)[1]
    assert '거래 URL을 먼저 등록하세요' in request('/?tab=my',returning)[1]
    assert 'Fixture Token' not in request('/?tab=my')[1]
    assert request('/?tab=buy',dict(buy,csrf='bad'))[0]==403
    assert '거래 URL을 먼저 등록하세요' in request('/?tab=buy',buy)[1]
    buyer_url='https://steamcommunity.com/tradeoffer/new/?partner=78493986&token=Abc_123-'
    assert request('/?tab=settings',dict(setting,trade_url=buyer_url))[0]==200
    assert '본인의 상품만 돌려받을 수 있습니다' in request('/?tab=my',returning)[1]
    empty_funds="session_name('botshop_game'); session_id($argv[1]); session_start(); $_SESSION['fixture_payment']=[]; session_write_close();"
    docker('exec',name,'php','-r',empty_funds,sid)
    status,body=request('/?tab=buy',buy)
    assert status==200 and 'class="purchase-toast"' in body and '키·금속이 부족' in body
    assert '구매 요청을 등록했습니다' not in body
    assert docker('exec',name,'php','-r',"$r=json_decode(file_get_contents('/tmp/botshop-test/users/listings.json'),true); echo count(reset($r)['orders']??[]);")=='0'
    docker('exec',name,'php','-r',"session_name('botshop_game'); session_id($argv[1]); session_start(); unset($_SESSION['fixture_payment']); session_write_close();",sid)
    for _ in range(2):assert '구매 요청을 등록했습니다' in request('/?tab=buy',buy)[1]
    assert '구매 거래제안 준비 중' in request('/?tab=my')[1]
    for tab in ['buy','sell','settings']:assert '내 구매·정산 진행 상태' not in request('/?tab='+tab)[1]
    assert '구매 연결 준비 중' not in request('/?tab=buy')[1]
    paid="require '/tmp/shop-app/settings.php'; require '/tmp/shop-app/listings.php'; require '/tmp/shop-app/checkout.php'; $d='/tmp/botshop-test'; $r=listingRead($d); $l=array_key_first($r); $o=array_key_first($r[$l]['orders']); $b=['listing'=>$l,'code'=>$o]; purchaseUpdate($d,$b+['status'=>'sent','buy_offer'=>'1001']); purchaseUpdate($d,$b+['status'=>'paid','buy_trade'=>'2001']); echo $o;"
    order=docker('exec',name,'php','-r',paid)
    claim={'action':'claim_payout','csrf':csrf,'listing':listing,'order':order}
    assert '본인의 판매대금만 받을 수 있습니다' in request('/?tab=my',claim)[1]
    game_token=seller_token;game_id='76561199077147589';last_grant=0;sid=seller_sid
    seller="session_name('botshop_game'); session_id($argv[1]); session_start(); $_SESSION['steamid']='76561199077147589'; session_write_close();"
    docker('exec',name,'php','-r',seller,sid)
    assert '판매되었습니다' in request('/?tab=my')[1] and '인벤토리로 판매대금 받기' in request('/?tab=my')[1]
    assert request('/?tab=my',dict(claim,csrf='bad'))[0]==403
    for _ in range(2):assert '판매대금 수령을 요청했습니다' in request('/?tab=my',claim)[1]
    assert '판매대금 수령 요청 완료' in request('/?tab=my')[1]
    assert 'value="claim_payout"' not in request('/?tab=my')[1]
    assert 'class="order-watermark"' not in request('/?tab=my')[1]
    settled="require '/tmp/shop-app/settings.php'; require '/tmp/shop-app/listings.php'; require '/tmp/shop-app/checkout.php'; $d='/tmp/botshop-test'; $r=listingRead($d); $l=array_key_first($r); $o=array_key_first($r[$l]['orders']); $b=['listing'=>$l,'code'=>$o]; purchaseUpdate($d,$b+['status'=>'settling','payout_offer'=>'3001']); purchaseUpdate($d,$b+['status'=>'settled','payout_trade'=>'4001']);"
    docker('exec',name,'php','-r',settled)
    assert 'class="order-watermark"' in request('/?tab=my')[1] and '거래성공' in request('/?tab=my')[1]
    assert 'order-success' in request('/?tab=my')[1]
    assert '<article class="card">' not in request('/?tab=my')[1]
    assert '완료·취소 내역' in request('/?tab=my')[1]
    assert '대금 미수령' not in request('/?tab=my')[1]
    return_fixture="require '/tmp/shop-app/settings.php'; require '/tmp/shop-app/listings.php'; listingWrite('/tmp/botshop-test',static function(&$r){$l=reset($r); $l['code']=str_repeat('e',32); $l['item']['ko']='Returned Fixture'; $l['orders']=[]; $l['returns']=[['status'=>'returned','created'=>time(),'updated'=>time()]]; $r[$l['code']]=$l;});"
    docker('exec',name,'php','-r',return_fixture)
    body=request('/?tab=my')[1]
    assert '반환 완료 · 내 인벤토리로 돌려받음' in body and '<article class="card">' not in body
    assert body.index('완료·취소 내역') < body.index('Returned Fixture')

    # Finance uses the same game identity; owner-only access and shortage before debit.
    docker('exec',name,'php','-r',"mkdir('/tmp/wallet-fixture');file_put_contents('/tmp/wallet-fixture/play.snapshot',time().\"\\n90 0\\n76561199077147589 90\\n\");require '/tmp/shop-app/listings.php';require '/tmp/shop-app/finance.php';financeWrite('/tmp/botshop-test',static function(&$d){$d['snapshot']=['time'=>time(),'counts'=>[],'report'=>[]];});")
    body=request('/?tab=points')[1]
    assert '게임 포인트' in body and '내 게임 잔액: 90포인트' in body
    nonce=docker('exec',name,'php','-r',"session_name('botshop_game');session_id($argv[1]);session_start();echo $_SESSION['finance_nonce'];",sid)
    status,body=request('/?tab=points',{'action':'finance','kind':'withdraw','csrf':csrf,'nonce':nonce,'points':'90','reason':''})
    assert status==200 and '아이템 포인트 충전·출금은 비활성화되었습니다' in body
    assert 'value="withdraw"' not in body and 'value="topup"' not in body
    assert '소유자만 사용할 수 있습니다' in request('/?tab=treasury')[1]
    denied=request('/?tab=treasury',{'action':'finance','kind':'capital_in','csrf':csrf,'nonce':nonce,'keys':'0','refined':'1'})[1]
    assert '소유자만 사용할 수 있습니다' in denied

    # Live grant required on every read and mutation; legacy cookies cannot restore it.
    assert request('/game-session.php')[0]==200
    old_token=game_token
    assert request('/auth.php',{'action':'logout'})[0]==200
    assert request('/?tab=my')[0]==403
    assert request('/?tab=settings',setting)[0]==403
    assert request('/market-api.php?ref='+market_ref)[0]==403
    game_token=''
    assert '게임에 접속한 Steam 계정:' not in request('/?tab=sell')[1]
    sid=authenticate('76561198038759714')
    assert '76561198038759714' in request('/?tab=sell')[1]
    docker('exec',name,'rm','/tmp/game-grants/'+game_token+'.json')
    last_grant=time.time()
    assert request('/?tab=settings')[0]==403
    sid=authenticate('76561198038759714')
    request('/?tab=sell')
    docker('exec',name,'php','-r',"session_name('botshop_game');session_id($argv[1]);session_start();$_SESSION['last_activity']=time()-301;session_write_close();",sid)
    assert request('/game-session.php')[0]==403
    sid=authenticate('76561198038759714')
    request('/?tab=sell')
    docker('exec',name,'php','-r',"file_put_contents('/tmp/game-grants/'.$argv[1].'.json',json_encode(['steamid'=>'76561199077147589','opened'=>time(),'expires'=>time()+15]));",game_token)
    last_grant=time.time()
    assert request('/?tab=my')[0]==403
    print('PASS game-bound auth, no cookies, account switching, revoked/deleted/idle sessions and all shop regression cases')
finally:
    subprocess.run(['docker','stop',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
