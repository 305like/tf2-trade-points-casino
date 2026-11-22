(function () {
    'use strict';
    var tip = document.getElementById('market-tip');
    if (!tip) return;
    var active = null, cache = {}, timer;
    var overlay = document.getElementById('market-link-overlay');
    var urlField = document.getElementById('market-link-url');
    var copyButton = document.getElementById('market-link-copy');
    var closeButton = document.getElementById('market-link-close');
    var status = document.getElementById('market-link-status'), opener;
    function dismissLink() {
        overlay.hidden = true;
        if (opener) opener.focus();
        close();
    }
    if (overlay) {
        closeButton.addEventListener('click', dismissLink);
        overlay.addEventListener('click', function (event) { if (event.target === overlay) dismissLink(); });
        overlay.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') { event.preventDefault(); dismissLink(); }
            if (event.key === 'Tab') {
                if (event.shiftKey && document.activeElement === urlField) { event.preventDefault(); closeButton.focus(); }
                else if (!event.shiftKey && document.activeElement === closeButton) { event.preventDefault(); urlField.focus(); }
            }
        });
        copyButton.addEventListener('click', function () {
            urlField.focus(); urlField.select();
            var copied = false;
            try { copied = document.execCommand('copy'); } catch (ignore) {}
            status.textContent = copied ? '주소를 복사했습니다.' : '선택된 주소를 Ctrl+C로 복사해 주세요.';
        });
    }
    function position(button) {
        var rect = button.closest('.backpack-item, .art').getBoundingClientRect();
        var left = rect.right + 6;
        if (left + tip.offsetWidth > window.innerWidth - 8) left = rect.left - tip.offsetWidth - 6;
        tip.style.left = Math.max(8, left) + 'px';
        tip.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - tip.offsetHeight - 8)) + 'px';
    }
    function show(button, data) {
        if (active !== button) return;
        var text = 'backpack.tf\n';
        if (data.unavailable) text += data.unavailable;
        else {
            text += data.name + '\n백팩 기준가: ' + (data.suggested || '등록 시세 없음');
            text += '\n판매 주문 최저: ' + (data.sell || (data.orders_ok ? '주문 없음' : '조회 불가'));
            text += '\n구매 주문 최고: ' + (data.buy || (data.orders_ok ? '주문 없음' : '조회 불가'));
            if (data.price_updated) text += '\n기준가 갱신: ' + new Date(data.price_updated * 1000).toLocaleDateString('ko-KR');
            text += '\n조회: ' + new Date(data.checked * 1000).toLocaleString('ko-KR');
            text += '\n조회된 주문 기준 · 체결가 아님\n파츠·페인트 추가 가치는 별도입니다.';
        }
        tip.textContent = text; position(button);
    }
    function open(button) {
        if (overlay && !overlay.hidden) return;
        clearTimeout(timer); active = button; tip.hidden = false;
        document.body.classList.add('market-tooltip-open');
        tip.textContent = 'backpack.tf 시세 조회 중…'; position(button);
        var ref = button.getAttribute('data-market-ref');
        if (cache[ref] && Date.now() - cache[ref].time < 300000) { show(button, cache[ref].data); return; }
        timer = setTimeout(function () {
            (window.BotShop ? window.BotShop.request('market-api.php?ref=' + encodeURIComponent(ref)) : fetch('market-api.php?ref=' + encodeURIComponent(ref), {credentials:'omit'}))
                .then(function (r) { return r.json().then(function (d) { if (r.ok) cache[ref] = {data:d,time:Date.now()}; return d; }); })
                .then(function (d) { show(button, d); })
                .catch(function () { show(button, {unavailable:'시세를 조회하지 못했습니다. 잠시 후 다시 확인해 주세요.'}); });
        }, 250);
    }
    function close() { clearTimeout(timer); active = null; tip.hidden = true; document.body.classList.remove('market-tooltip-open'); }
    document.querySelectorAll('[data-market-ref]').forEach(function (button) {
        button.addEventListener('mouseenter', function () { open(button); });
        button.addEventListener('focus', function () { open(button); });
        button.addEventListener('click', function (event) {
            event.preventDefault(); event.stopPropagation(); close();
            if (!overlay) return;
            opener = button; urlField.value = button.getAttribute('data-market-url');
            status.textContent = ''; overlay.hidden = false;
            urlField.focus(); urlField.select();
        });
        button.addEventListener('mouseleave', close);
        button.addEventListener('blur', close);
        button.addEventListener('keydown', function (event) { if (event.key === 'Escape') { event.preventDefault(); close(); } });
    });
    window.addEventListener('scroll', close, true);
    window.addEventListener('resize', close);
}());
