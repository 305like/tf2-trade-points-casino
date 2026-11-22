<?php
declare(strict_types=1);
require __DIR__.'/game-session.php';
header('Cache-Control: no-store');header('Content-Type: application/json; charset=utf-8');
if(($_SERVER['REQUEST_METHOD']??'')!=='POST'||($_POST['action']??'')!=='logout'||!shopSessionStart(false)){
    http_response_code(403);echo json_encode(['error'=>'게임에서 !봇거래를 열어 주세요.'],JSON_UNESCAPED_UNICODE);exit;
}
$_SESSION=['revoked'=>true];session_write_close();echo '{"ok":true}';
