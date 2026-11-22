(function () {
    'use strict';
    var token = location.hash.slice(1), frame = document.getElementById('game-shop');
    var status = document.getElementById('game-status'), busy = false, poll;
    var initialTab = new URL(location.href).searchParams.get('tab');
    if (['points','treasury'].indexOf(initialTab) === -1) initialTab = 'sell';
    history.replaceState(null, '', location.pathname);
    function endpoint(value) {
        var url = new URL(value, location.href);
        if (url.origin !== location.origin || !/^\/bot-shop\/(?:index\.php|market-api\.php|game-session\.php|auth\.php)?$/.test(url.pathname)) throw Error('Invalid endpoint');
        return url;
    }
    function stop() {
        token = ''; clearInterval(poll); frame.hidden = true; frame.removeAttribute('srcdoc');
        status.hidden = false; status.textContent = '상점 연결이 종료되었습니다. 게임에서 !봇거래를 다시 열어 주세요.';
    }
    function request(value, options) {
        if (!token) return Promise.reject(Error('Closed session'));
        var url = endpoint(value), opts = options || {};
        opts.credentials = 'omit'; opts.cache = 'no-store'; opts.redirect = 'error';
        opts.headers = {'X-Botshop-Session': token};
        if (opts.body) opts.headers['Content-Type'] = 'application/x-www-form-urlencoded';
        return fetch(url.href, opts).then(function (response) {
            if (response.status === 403 && (url.pathname.indexOf('game-session.php') !== -1 || (response.headers.get('Content-Type') || '').indexOf('application/json') !== -1)) { stop(); throw Error('Expired session'); }
            return response;
        });
    }
    function navigate(value, options) {
        if (busy || !token) return;
        var url = endpoint(value);
        if (url.pathname.endsWith('auth.php')) { logout(); return; }
        busy = true; document.body.classList.add('busy');
        request(url.href, options).then(function (response) { return response.text(); }).then(function (html) {
            if (!token) return;
            // A new document releases the previous page, listeners and item images.
            window.BotShop.currentURL = url.href; frame.srcdoc = html; frame.hidden = false; status.hidden = true;
            frame.onload = function () {
                var anchor = url.hash && frame.contentDocument.getElementById(url.hash.slice(1));
                if (anchor) anchor.scrollIntoView();
            };
        }).catch(function () { if (token) { status.hidden = false; status.textContent = '상점 연결을 확인하지 못했습니다. 잠시 후 다시 시도하세요.'; } })
            .then(function () { busy = false; document.body.classList.remove('busy'); });
    }
    function logout() {
        if (token) request('auth.php', {method:'POST',body:'action=logout',keepalive:true}).catch(function () {});
        stop();
    }
    window.BotShop = {navigate:navigate, request:request};
    window.addEventListener('pagehide', logout);
    if (!/^[a-f0-9]{64}$/.test(token)) { stop(); return; }
    navigate('index.php?tab=' + initialTab);
    poll = setInterval(function () { if (token) request('game-session.php').catch(stop); }, 5000);
}());
