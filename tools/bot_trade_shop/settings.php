<?php
declare(strict_types=1);
class TradeSettingsException extends RuntimeException {}
function validTradeURL(string $id,string $url): string {
    if(PHP_INT_SIZE<8||!preg_match('/\A7656119[0-9]{10}\z/D',$id))throw new InvalidArgumentException('Steam 본인 확인이 필요합니다.');
    $account=(string)((int)$id-76561197960265728);
    if(!preg_match('~\Ahttps://steamcommunity\.com/tradeoffer/new/\?partner='.preg_quote($account,'~').'&token=[A-Za-z0-9_-]{8}\z~D',trim($url)))
        throw new InvalidArgumentException('로그인한 본인 계정의 Steam 거래 URL을 입력하세요.');
    return trim($url);
}
function tradeURLFile(string $dir,string $id): string {
    if(!preg_match('/\A7656119[0-9]{10}\z/D',$id))throw new RuntimeException('Invalid identity');
    return $dir.'/users/trade-url-'.$id.'.txt';
}
function readTradeURL(string $dir,string $id): string {
    $file=tradeURLFile($dir,$id);
    if(!is_readable(dirname($file)))throw new TradeSettingsException('Trade settings unavailable');
    if(!file_exists($file))return '';
    $url=@file_get_contents($file);if($url===false)throw new TradeSettingsException('Trade settings unavailable');
    return validTradeURL($id,$url);
}
function saveTradeURL(string $dir,string $id,string $url): void {
    $url=validTradeURL($id,$url);$file=tradeURLFile($dir,$id);
    $folder=dirname($file);
    if(!is_dir($folder)||!is_writable($folder))throw new TradeSettingsException('Trade settings storage unavailable');
    $temp=tempnam($folder,'url-');if($temp===false)throw new TradeSettingsException('Trade settings staging failed');
    try {
        if(!chmod($temp,0600)||file_put_contents($temp,$url)!==strlen($url)||!rename($temp,$file))throw new TradeSettingsException('Trade settings save failed');
    } finally {if(file_exists($temp))unlink($temp);}
}
