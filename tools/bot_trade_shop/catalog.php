<?php
declare(strict_types=1);

function field(array $input, string $key, int $max): string {
    $v = $input[$key] ?? '';
    if (!is_string($v) || strlen($v) > $max || !preg_match('//u', $v) || preg_match('/[\x00-\x1f\x7f]/', $v)) throw new InvalidArgumentException('문자 입력을 확인하세요.');
    return trim($v);
}
function product(array $input): array {
    $name = field($input, 'name', 120);
    $market = field($input, 'market', 180);
    $image = field($input, 'image', 1000);
    if ($name === '' || $market === '') throw new InvalidArgumentException('상품명과 정확한 Steam 상품명을 입력하세요.');
    // Only browser-loaded Steam images; never fetch administrator URLs on the server.
    if ($image !== '' && !preg_match('~\Ahttps://(?:community\.akamai\.steamstatic\.com|community\.cloudflare\.steamstatic\.com|steamcommunity-a\.akamaihd\.net)/economy/image/[A-Za-z0-9_./-]+\z~D', $image)) throw new InvalidArgumentException('Steam economy/image 이미지 주소만 사용할 수 있습니다.');
    $row = ['name'=>$name, 'market'=>$market, 'image'=>$image];
    foreach (['buy', 'sell', 'stock'] as $key) {
        $value = field($input, $key, 8);
        if (!preg_match('/\A(?:0|[1-9][0-9]{0,6})\z/D', $value)) throw new InvalidArgumentException('가격과 수량은 0~9999999 정수로 입력하세요.');
        $row[$key] = (int)$value;
    }
    $row['buy_enabled'] = ($input['buy_enabled'] ?? '') === '1';
    $row['sell_enabled'] = ($input['sell_enabled'] ?? '') === '1';
    return $row;
}
function readCatalog(string $dir): array {
    $file = $dir.'/catalog.json';
    if (!file_exists($file)) return [];
    $rows = json_decode((string)file_get_contents($file), true, 16, JSON_THROW_ON_ERROR);
    if (!is_array($rows) || count($rows)>200) throw new RuntimeException('catalog');
    return $rows;
}
function saveProduct(string $dir, array $row): void {
    $lock = fopen($dir.'/catalog.lock', 'c');
    if (!$lock || !flock($lock, LOCK_EX)) throw new RuntimeException('lock');
    try {
        $rows = readCatalog($dir);
        foreach ($rows as $existing) if ($existing['market'] === $row['market']) throw new InvalidArgumentException('이미 등록된 Steam 상품명입니다. 기존 상품을 숨긴 경우에도 중복 등록할 수 없습니다.');
        if (count($rows)>=200) throw new InvalidArgumentException('상품은 최대 200개까지 등록할 수 있습니다.');
        $row['id'] = bin2hex(random_bytes(8)); $rows[] = $row;
        $json = json_encode($rows, JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
        $temp = tempnam($dir, 'catalog-');
        if ($temp===false) throw new RuntimeException('temp');
        try {
            chmod($temp,0600);
            if (file_put_contents($temp,$json)!==strlen($json) || !rename($temp,$dir.'/catalog.json')) throw new RuntimeException('save');
        } finally { if (file_exists($temp)) unlink($temp); }
    } finally { flock($lock,LOCK_UN); fclose($lock); }
}
