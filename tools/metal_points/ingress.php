<?php
// Only the authenticated bot may submit Steam-verified receipts. Never a client balance API.
ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
function reply($status, $data) { http_response_code($status); echo json_encode($data); exit; }
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') reply(405, ['error'=>'POST required']);
$root = dirname(__DIR__, 2);
$secret = @file_get_contents($root.'/.metal-points-private/token.sha256');
$auth = $_SERVER['HTTP_X_METAL_TOKEN'] ?? '';
if (!$secret || strlen($auth) !== 64 || !hash_equals(trim($secret), hash('sha256', $auth))) reply(403, ['error'=>'authentication']);
$raw = file_get_contents('php://input', false, null, 0, 1025);
if (strlen($raw) > 1024) reply(413, ['error'=>'body too large']);
$b = json_decode($raw, true);
if ($b === ['health'=>true]) {
    $stamp = (int) @file_get_contents($root.'/tf/addons/sourcemod/data/metal_points/ready');
    reply(200, ['ok'=>true, 'ready'=>false, 'ledger_ready'=>time()-$stamp >= 0 && time()-$stamp < 30, 'item_points_enabled'=>false]);
}
$dir = $root.'/tf/addons/sourcemod/data/metal_points';
if(in_array($b['action']??'', ['claim','bind'],true))reply(200,['ok'=>true,'status'=>'denied']);
if (is_array($b) && ($b['action'] ?? '')==='reject') {
    if (!is_string($b['code'] ?? null) || !preg_match('/\A[a-f0-9]{32}\z/D',$b['code'])
        || !is_string($b['steamid'] ?? null) || !preg_match('/\A7656119[0-9]{10}\z/D',$b['steamid'])
        || !is_int($b['points'] ?? null) || $b['points']<5760 || $b['points']>90000 || $b['points']%10!==0) reply(400,['error'=>'rejection']);
    $base=$dir.'/'.$b['code'].'.reject';
    $line=implode(' ',[$b['code'],$b['steamid'],$b['points']])."\n";
    $lock=@fopen($dir.'/.ingress.lock','r') ?: @fopen($dir.'/.ingress.lock','c');
    if(!$lock || !flock($lock,LOCK_EX)) reply(503,['error'=>'busy']);
    $done=@file_get_contents($base.'.done');
    if($done!==false) {
        $parts=explode("\n",$done);
        if($parts[0]."\n"!==$line) reply(409,['error'=>'conflict']);
        reply(200,['ok'=>true,'status'=>$parts[1] ?? 'denied']);
    }
    $previous=@file_get_contents($base);
    if($previous!==false && $previous!==$line) reply(409,['error'=>'conflict']);
    if($previous===false && (file_put_contents($base.'.tmp',$line,LOCK_EX)!==strlen($line) || !chmod($base.'.tmp',0644) || !rename($base.'.tmp',$base))) reply(503,['error'=>'queue']);
    reply(200,['ok'=>true,'status'=>'queued']);
}
if ($b === ['action'=>'outgoing']) {
    reply(200,['ok'=>true,'requests'=>[]]); // Item withdrawals disabled; legacy ledger retained.
    $lines=@file($dir.'/outgoing.queue', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!$lines || time()-(int)$lines[0]<0 || time()-(int)$lines[0]>30) reply(200,['ok'=>true,'requests'=>[]]);
    $rows=[];
    foreach (array_slice($lines,1) as $line) {
        $f=explode(' ',$line);
        if(count($f)!==4) reply(503,['error'=>'queue']);
        $rows[]=['code'=>$f[0],'steamid'=>$f[1],'points'=>(int)$f[2],'url'=>$f[3]];
    }
    reply(200,['ok'=>true,'requests'=>$rows]);
}
if (is_array($b) && in_array($b['action'] ?? '', ['claim','bind','sent','settle'], true)) {
    $action=$b['action'];
    if (!is_string($b['offer'] ?? null) || !preg_match('/\A[1-9][0-9]{0,19}\z/D',$b['offer'])
        || !is_string($b['code'] ?? null) || !preg_match('/\A[a-f0-9]{32}\z/D',$b['code'])
        || !is_string($b['steamid'] ?? null) || !preg_match('/\A7656119[0-9]{10}\z/D',$b['steamid'])
        || !is_int($b['points'] ?? null) || $b['points']<10 || $b['points']>90000 || $b['points']%10!==0) reply(400,['error'=>'withdrawal']);
    $line=implode(' ',[$b['offer'],$b['code'],$b['steamid'],$b['points']]);
    if ($action==='settle') {
        if (!in_array($b['result'] ?? '',['completed','failed'],true) || !is_string($b['trade'] ?? null) || !preg_match('/\A[0-9]{1,20}\z/D',$b['trade'])) reply(400,['error'=>'settlement']);
        $line.=' '.$b['result'].' '.$b['trade'];
    }
    $line.="\n";
    $base=$dir.'/'.$b['offer'].'.'.$action;
    // Hosting restarts can reassign lock ownership; flock only needs a readable descriptor.
    $lock=@fopen($dir.'/.ingress.lock','r') ?: @fopen($dir.'/.ingress.lock','c');
    if (!$lock || !flock($lock,LOCK_EX)) reply(503,['error'=>'busy']);
    $previous=@file_get_contents($base);
    $done=@file_get_contents($base.'.done');
    if ($done!==false) {
        $parts=explode("\n",$done);
        if (($parts[0]."\n")!==$line) reply(409,['error'=>'conflict']);
        reply(200,['ok'=>true,'status'=>$parts[1] ?? 'invalid']);
    }
    if ($previous!==false && $previous!==$line) reply(409,['error'=>'conflict']);
    if ($previous===false && (file_put_contents($base.'.tmp',$line,LOCK_EX)!==strlen($line) || !chmod($base.'.tmp',0644) || !rename($base.'.tmp',$base))) reply(503,['error'=>'queue']);
    reply(200,['ok'=>true,'status'=>'queued']);
}
if (!is_array($b) || count($b) !== 4) reply(400, ['error'=>'receipt']);
foreach (['trade','offer'] as $key) {
    if (!is_string($b[$key] ?? null) || !preg_match('/\A[1-9][0-9]{0,19}\z/D', $b[$key])) reply(400, ['error'=>'id']);
}
if (!is_string($b['steamid'] ?? null) || !preg_match('/\A7656119[0-9]{10}\z/D', $b['steamid'])) reply(400, ['error'=>'steamid']);
if (!is_int($b['points'] ?? null) || $b['points'] < 10 || $b['points'] > 90000 || $b['points'] % 10 !== 0) reply(400, ['error'=>'points']);
$line = implode(' ', [$b['trade'],$b['offer'],$b['steamid'],$b['points']])."\n";
$base = $dir.'/'.$b['trade'];
$lock = @fopen($dir.'/.ingress.lock', 'r') ?: @fopen($dir.'/.ingress.lock', 'c');
if (!$lock || !flock($lock, LOCK_EX)) reply(503, ['error'=>'mailbox locked']);
foreach (['done','evt'] as $suffix) {
    $previous = @file_get_contents($base.'.'.$suffix);
    if ($previous !== false) {
        if ($previous !== $line) reply(409, ['error'=>'conflicting receipt']);
        reply(200, ['ok'=>true,'status'=>$suffix === 'done' ? 'credited' : 'queued']);
    }
}
$tmp = $base.'.tmp';
if (file_put_contents($tmp, $line, LOCK_EX) !== strlen($line) || !chmod($tmp, 0644) || !rename($tmp, $base.'.evt')) reply(503, ['error'=>'queue unavailable']);
reply(200, ['ok'=>true,'status'=>'queued']);
