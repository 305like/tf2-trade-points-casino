<?php
declare(strict_types=1);
ini_set('display_errors','0');header('Content-Type: application/json; charset=utf-8');header('Cache-Control: no-store');header('X-Content-Type-Options: nosniff');
require __DIR__.'/market.php';require __DIR__.'/steam.php';require __DIR__.'/settings.php';require __DIR__.'/listings.php';
require __DIR__.'/game-session.php';
shopSessionStart();
try{
    if(($_SERVER['REQUEST_METHOD']??'GET')!=='GET')throw new InvalidArgumentException('method');
    $ref=$_GET['ref']??'';
    if(!is_string($ref)||!isset($_SESSION['market_items'][$ref]))throw new InvalidArgumentException('item');
    $row=$_SESSION['market_items'][$ref];
    if(($row['until']??0)<time())throw new InvalidArgumentException('expired');
    if(session_status()===PHP_SESSION_ACTIVE)session_write_close();
    $dir=getenv('BOTSHOP_DATA_DIR')?:dirname(__DIR__,2).'/.bot-trade-shop-private';
    echo json_encode(marketFetch($dir,$row),JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
}catch(InvalidArgumentException $e){http_response_code(400);echo json_encode(['unavailable'=>'페이지를 새로 연 뒤 확인해 주세요.'],JSON_UNESCAPED_UNICODE);}
catch(Throwable $e){http_response_code(503);echo json_encode(['unavailable'=>'시세를 조회하지 못했습니다. 잠시 후 다시 확인해 주세요.'],JSON_UNESCAPED_UNICODE);}
