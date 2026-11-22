<?php
declare(strict_types=1);
require __DIR__.'/catalog.php';
function check(bool $v): void {if(!$v)throw new RuntimeException('test failed');}
$base=['name'=>'상품 <script>alert(1)</script>','market'=>'Test Item','image'=>'','buy'=>'100','sell'=>'90','stock'=>'2','buy_enabled'=>'1','sell_enabled'=>'1'];
$row=product($base);check($row['buy']===100 && $row['sell_enabled']);
foreach ([['buy'=>'-1'],['stock'=>'1.5'],['sell'=>'10000000'],['buy'=>[]],['name'=>"bad\nname"],['market'=>''],['image'=>'javascript:alert(1)'],['image'=>'https://example.com/a.png'],['image'=>'https://community.akamai.steamstatic.com.evil.test/economy/image/a']] as $bad) {
    try {product(array_replace($base,$bad));throw new RuntimeException('invalid input accepted');}catch(InvalidArgumentException $expected){}
}
check(product(array_replace($base,['image'=>'https://community.akamai.steamstatic.com/economy/image/abc_123/256fx256f']))['stock']===2);
$dir=sys_get_temp_dir().'/botshop-test-'.bin2hex(random_bytes(8));mkdir($dir,0700);
try {
    check(readCatalog($dir)===[]);saveProduct($dir,$row);check(count(readCatalog($dir))===1);
    try {saveProduct($dir,$row);throw new RuntimeException('duplicate accepted');}catch(InvalidArgumentException $expected){}
    check(count(readCatalog($dir))===1);
    check(strpos(file_get_contents($dir.'/catalog.json'),'Test Item')!==false);
    file_put_contents($dir.'/catalog.json','broken');
    try {readCatalog($dir);throw new RuntimeException('corruption accepted');}catch(JsonException $expected){}
} finally {foreach(['catalog.json','catalog.lock'] as $f)if(file_exists($dir.'/'.$f))unlink($dir.'/'.$f);rmdir($dir);}
echo "PASS product validation, Steam image allowlist, duplicate protection, persistence, corruption fail-closed\n";
