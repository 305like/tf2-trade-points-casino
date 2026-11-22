<?php
header('Cache-Control: no-store');header('Referrer-Policy: no-referrer');header('X-Content-Type-Options: nosniff');
header("Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' https://community.akamai.steamstatic.com https://community.cloudflare.steamstatic.com https://steamcommunity-a.akamaihd.net; frame-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
if(isset($_COOKIE['botshop']))setcookie('botshop','',['expires'=>1,'path'=>'/','secure'=>true,'httponly'=>true,'samesite'=>'Lax']);
?><!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>봇거래</title><link rel="stylesheet" href="game.css?v=1"><script src="game.js?v=20261031-finance" defer></script></head><body><p id="game-status" role="status">게임 계정 연결을 확인하고 있습니다.</p><iframe id="game-shop" title="봇거래 상점" hidden></iframe></body></html>
