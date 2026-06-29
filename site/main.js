/* Flutter Radar — site interactivity.
   Three jobs: scroll-reveal, code-tab toggles, reduced-motion respect.
   Everything degrades to a fully usable static page if JS never runs. */
(function () {
  'use strict';

  var prefersReducedMotion = window.matchMedia(
    '(prefers-reduced-motion: reduce)'
  ).matches;

  /* ---- Scroll reveal -----------------------------------------------------
     Fade + rise on intersection. Under reduced motion (or no IO support) we
     reveal everything immediately so nothing stays invisible. */
  function setupReveal() {
    var els = document.querySelectorAll('[data-reveal]');
    if (!els.length) return;

    if (prefersReducedMotion || !('IntersectionObserver' in window)) {
      els.forEach(function (el) {
        el.classList.add('is-revealed');
      });
      return;
    }

    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-revealed');
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -7% 0px' }
    );

    els.forEach(function (el) {
      io.observe(el);
    });

    /* Safety net: if something never intersects (e.g. tall viewport), reveal
       it after a beat so content is never trapped at opacity 0. */
    window.setTimeout(function () {
      els.forEach(function (el) {
        el.classList.add('is-revealed');
      });
    }, 4000);
  }

  /* ---- Code tabs ---------------------------------------------------------
     A [data-tabs] container holds role="tab" buttons (aria-controls -> panel
     id) and the panels themselves. Keyboard: arrows move + activate, Home/End
     jump to ends. Pure transform/opacity-free swap (display toggle). */
  function setupTabs() {
    var groups = document.querySelectorAll('[data-tabs]');
    groups.forEach(function (group) {
      var tabs = Array.prototype.slice.call(
        group.querySelectorAll('[role="tab"]')
      );
      if (!tabs.length) return;

      function activate(tab, focus) {
        tabs.forEach(function (t) {
          var selected = t === tab;
          t.setAttribute('aria-selected', selected ? 'true' : 'false');
          t.setAttribute('tabindex', selected ? '0' : '-1');
          var panel = document.getElementById(t.getAttribute('aria-controls'));
          if (panel) panel.hidden = !selected;
        });
        if (focus) tab.focus();
      }

      tabs.forEach(function (tab, index) {
        tab.addEventListener('click', function () {
          activate(tab, false);
        });
        tab.addEventListener('keydown', function (event) {
          var next = null;
          switch (event.key) {
            case 'ArrowRight':
            case 'ArrowDown':
              next = tabs[(index + 1) % tabs.length];
              break;
            case 'ArrowLeft':
            case 'ArrowUp':
              next = tabs[(index - 1 + tabs.length) % tabs.length];
              break;
            case 'Home':
              next = tabs[0];
              break;
            case 'End':
              next = tabs[tabs.length - 1];
              break;
            default:
              return;
          }
          event.preventDefault();
          activate(next, true);
        });
      });
    });
  }

  function init() {
    setupReveal();
    setupTabs();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
