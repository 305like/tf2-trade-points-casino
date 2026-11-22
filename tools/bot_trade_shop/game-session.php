<?php
declare(strict_types=1);

function shopGameGrant(string $token, int $now): array {
    if(!preg_match('/\A[a-f0-9]{64}\z/D',$token))throw new RuntimeException('Invalid game session');
    $dir=getenv('BOTSHOP_GAME_DIR')?:dirname(__DIR__,2).'/tf/addons/sourcemod/data/bot_trade_shop_sessions';
    $raw=@file_get_contents($dir.'/'.$token.'.json');
    $grant=$raw===false?null:json_decode($raw,true);
    if(!is_array($grant)||!is_string($grant['steamid']??null)||!preg_match('/\A7656119[0-9]{10}\z/D',$grant['steamid'])
        ||!is_int($grant['expires']??null)||$grant['expires']<=$now||$grant['expires']>$now+30
        ||!is_int($grant['opened']??null)||$grant['opened']>$now||$now-$grant['opened']>=1800)
        throw new RuntimeException('Expired game session');
    return $grant;
}

function shopSessionStart(bool $touch=true): bool {
    // The legacy browser cookie and PHPSESSID are never authentication inputs.
    $token=$_SERVER['HTTP_X_BOTSHOP_SESSION']??'';
    if($token===''){$_SESSION=['csrf'=>bin2hex(random_bytes(24))];return false;}
    try {
        $grant=shopGameGrant($token,time());
        ini_set('session.use_cookies','0');ini_set('session.use_only_cookies','0');ini_set('session.use_trans_sid','0');
        // Only an existing, game-owned capability may choose this server-side session.
        ini_set('session.use_strict_mode','0');session_name('botshop_game');
        session_id(hash('sha256','botshop-game:'.$token));
        if(!session_start())throw new RuntimeException('Session storage unavailable');
        if(!empty($_SESSION['revoked'])||isset($_SESSION['steamid'])&&$_SESSION['steamid']!==$grant['steamid']
            ||isset($_SESSION['last_activity'])&&time()-$_SESSION['last_activity']>=300)
            throw new RuntimeException('Game session closed');
        $_SESSION['steamid']=$grant['steamid'];$_SESSION['steam_until']=$grant['expires'];
        if(!isset($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(24));
        if($touch||!isset($_SESSION['last_activity']))$_SESSION['last_activity']=time();
        return true;
    } catch(Throwable $e) {
        if(session_status()===PHP_SESSION_ACTIVE){$_SESSION=['revoked'=>true];session_write_close();}
        http_response_code(403);header('Content-Type: application/json; charset=utf-8');header('Cache-Control: no-store');
        echo json_encode(['error'=>'상점 연결이 종료되었습니다. 게임에서 !봇거래를 다시 열어 주세요.'],JSON_UNESCAPED_UNICODE);exit;
    }
}

if(realpath($_SERVER['SCRIPT_FILENAME']??'')===__FILE__){
    header('Cache-Control: no-store');header('Content-Type: application/json; charset=utf-8');
    if(!shopSessionStart(false)){http_response_code(403);echo '{"ok":false}';exit;}
    session_write_close();echo '{"ok":true}';
}
