(function () {
    'use strict';
    if (window.parent === window || !window.parent.BotShop) return;
    var shop = window.parent.BotShop, submitter;
    window.BotShop = shop;
    document.addEventListener('click', function (event) {
        var button = event.target.closest('button,input[type=submit]');
        if (button) submitter = button;
        var link = event.target.closest('a[href]');
        if (!link) return;
        var url = new URL(link.getAttribute('href'), shop.currentURL);
        if (url.origin !== window.parent.location.origin) return;
        if (!/^\/bot-shop\/(?:index\.php)?$/.test(url.pathname)) return;
        event.preventDefault(); shop.navigate(url.href);
    });
    document.addEventListener('submit', function (event) {
        var form = event.target, clicked = event.submitter || submitter;
        var url = new URL(form.getAttribute('action') || 'index.php', shop.currentURL);
        if (url.origin !== window.parent.location.origin) { event.preventDefault(); return; }
        // srcdoc resolves ?tab links against game.php; all shop navigation goes to index.php.
        if (url.pathname.endsWith('game.php')) url.pathname = '/bot-shop/index.php';
        event.preventDefault();
        var data = new URLSearchParams(new FormData(form));
        if (clicked && clicked.form === form && clicked.name) data.append(clicked.name, clicked.value);
        submitter = null;
        if (form.method.toLowerCase() === 'get') { url.search = data.toString(); shop.navigate(url.href); }
        else shop.navigate(url.href, {method:'POST',body:data.toString()});
    });
    window.shopNavigate = function (url) { shop.navigate(new URL(url, shop.currentURL).href); };
}());
