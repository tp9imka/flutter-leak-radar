/* =============================================
   Flutter Leak Radar — Landing Page JS
   No framework. No build step.
   ============================================= */

(function () {
  'use strict';

  /* ——————————————————————————————————————————
     Reduced-motion gate
  —————————————————————————————————————————— */
  const prefersReducedMotion = window.matchMedia(
    '(prefers-reduced-motion: reduce)'
  ).matches;

  /* ——————————————————————————————————————————
     SVG draw-in: seed stroke-dasharray/offset
  —————————————————————————————————————————— */
  function initDrawPaths() {
    document.querySelectorAll('[data-draw]').forEach(function (path) {
      try {
        var len = path.getTotalLength();
        path.style.strokeDasharray = len;
        path.style.strokeDashoffset = len;
        if (prefersReducedMotion) {
          path.style.strokeDashoffset = '0';
        }
      } catch (e) {
        // SVG might not support getTotalLength in some environments
      }
    });
  }

  /* ——————————————————————————————————————————
     IntersectionObserver: scroll reveals + draw-in
  —————————————————————————————————————————— */
  function initReveal() {
    if (!('IntersectionObserver' in window)) {
      // Fallback: reveal everything immediately
      forceRevealAll();
      return;
    }

    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          var el = entry.target;

          if (el.hasAttribute('data-reveal')) {
            el.style.opacity = '1';
            el.style.transform = 'none';
          }

          if (el.hasAttribute('data-draw') && !prefersReducedMotion) {
            el.style.transition = 'stroke-dashoffset 1.5s cubic-bezier(.4,0,.2,1)';
            el.style.strokeDashoffset = '0';
          } else if (el.hasAttribute('data-draw') && prefersReducedMotion) {
            el.style.strokeDashoffset = '0';
          }

          io.unobserve(el);
        });
      },
      { threshold: 0.18, rootMargin: '0px 0px -8% 0px' }
    );

    document.querySelectorAll('[data-reveal], [data-draw]').forEach(function (el) {
      io.observe(el);
    });

    // Safety timeout: force-reveal everything hidden after 4s
    var safetyTimer = setTimeout(forceRevealAll, 4000);

    // Clean up safety timer once page is visible
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) {
        clearTimeout(safetyTimer);
        safetyTimer = setTimeout(forceRevealAll, 4000);
      }
    });
  }

  function forceRevealAll() {
    document.querySelectorAll('[data-reveal]').forEach(function (el) {
      el.style.opacity = '1';
      el.style.transform = 'none';
    });
    document.querySelectorAll('[data-draw]').forEach(function (el) {
      el.style.strokeDashoffset = '0';
    });
  }

  /* ——————————————————————————————————————————
     Tab toggle: Runtime detector / Lint diagnostic
  —————————————————————————————————————————— */
  function initTabs() {
    var tabRuntime = document.getElementById('tab-runtime');
    var tabLint    = document.getElementById('tab-lint');
    if (!tabRuntime || !tabLint) return;

    var codeRuntime  = document.getElementById('code-runtime');
    var codeLint     = document.getElementById('code-lint');
    var sideRuntime  = document.getElementById('side-runtime');
    var sideLint     = document.getElementById('side-lint');
    var filename     = document.getElementById('code-filename');

    function setTab(active) {
      var isRuntime = active === 'runtime';

      // Tab button states
      tabRuntime.classList.toggle('tab-active', isRuntime);
      tabLint.classList.toggle('tab-active', !isRuntime);
      tabRuntime.setAttribute('aria-selected', isRuntime ? 'true' : 'false');
      tabLint.setAttribute('aria-selected', isRuntime ? 'false' : 'true');

      // Code panels
      codeRuntime.classList.toggle('hidden', !isRuntime);
      codeLint.classList.toggle('hidden', isRuntime);

      // Side panels
      sideRuntime.classList.toggle('hidden', !isRuntime);
      sideLint.classList.toggle('hidden', isRuntime);

      // Filename in editor title bar
      filename.textContent = isRuntime ? 'main.dart' : 'chat_screen.dart';
    }

    tabRuntime.addEventListener('click', function () { setTab('runtime'); });
    tabLint.addEventListener('click',    function () { setTab('lint'); });

    // Keyboard: arrow keys navigate between tabs
    [tabRuntime, tabLint].forEach(function (btn, idx, arr) {
      btn.addEventListener('keydown', function (e) {
        var next;
        if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
          next = arr[(idx + 1) % arr.length];
        } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
          next = arr[(idx - 1 + arr.length) % arr.length];
        }
        if (next) {
          next.focus();
          next.click();
          e.preventDefault();
        }
      });
    });

    // Default: runtime
    setTab('runtime');
  }

  /* ——————————————————————————————————————————
     Hover effects for nav links (JS-free fallback
     handled in CSS; this adds smooth color)
     Nothing needed beyond CSS here.
  —————————————————————————————————————————— */

  /* ——————————————————————————————————————————
     Init
  —————————————————————————————————————————— */
  function init() {
    initDrawPaths();
    initReveal();
    initTabs();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
