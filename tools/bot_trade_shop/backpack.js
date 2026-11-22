(function () {
    'use strict';
    var toast = document.querySelector('.purchase-toast');
    if (toast) window.setTimeout(function () { toast.remove(); }, 3000);
    var dialog = document.querySelector('.confirm-modal');
    if (dialog) {
        dialog.focus();
        dialog.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') { if (window.shopNavigate) window.shopNavigate('?tab=sell'); else window.location.href = '?tab=sell'; return; }
            if (event.key !== 'Tab') return;
            var items = dialog.querySelectorAll('a[href], button:not(:disabled), input:not([type=hidden])');
            if (!items.length) return;
            var first = items[0], last = items[items.length - 1];
            if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) { event.preventDefault(); last.focus(); }
            else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
        });
    }

    document.querySelectorAll('[data-color]').forEach(function (element) {
        var color = element.getAttribute('data-color');
        if (/^[0-9a-f]{6}$/i.test(color)) element.style.color = '#' + color;
    });
    document.querySelectorAll('.backpack-grid').forEach(function (grid) {
        var selected = grid.querySelector('input:checked');
        grid.addEventListener('click', function (event) {
            var input = event.target;
            if (!input.matches('input[name="assetid"]')) return;
            input.checked = selected !== input;
            selected = input.checked ? input : null;
        });
        grid.addEventListener('change', function (event) {
            if (event.target.matches('input[name="assetid"]')) selected = event.target.checked ? event.target : null;
        });
        grid.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') {
                grid.classList.add('hide-tooltips');
            } else grid.classList.remove('hide-tooltips');
        });
        function positionTooltip(event) {
            var item = event.target.closest('.backpack-item');
            if (!item) return;
            grid.classList.remove('hide-tooltips');
            var tip = item.querySelector('.item-tooltip'), rect = item.getBoundingClientRect();
            var left = rect.right + 6;
            if (left + tip.offsetWidth > window.innerWidth - 8) left = rect.left - tip.offsetWidth - 6;
            tip.style.left = Math.max(8, left) + 'px';
            tip.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - tip.offsetHeight - 8)) + 'px';
        }
        grid.addEventListener('mouseover', positionTooltip);
        grid.addEventListener('focusin', positionTooltip);
        window.addEventListener('scroll', function (event) {
            if (event.target.classList && event.target.classList.contains('item-tooltip')) return;
            grid.classList.add('hide-tooltips');
        }, true);
    });
}());
