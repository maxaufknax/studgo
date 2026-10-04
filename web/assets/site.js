/* Verhalten der Landing Page: Laufband, Kopfzeile, Aurora, Einblenden.
   Liegt als eigene Datei vor, weil die Content-Security-Policy der Seite
   keine Inline-Skripte zulässt (script-src 'self'). */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Laufband: Inhalt genau einmal duplizieren und die Laufzeit an die
     Breite koppeln. Ohne JavaScript stehen die Chips still, mit reduzierter
     Bewegung ebenfalls. */
  var track = document.getElementById("chips");
  if (track && !reduce) {
    var base = track.innerHTML;
    track.innerHTML = base + base;
    var width = track.scrollWidth / 2;
    track.style.setProperty("--marquee-s", Math.max(18, width / 55) + "s");
  }

  /* Kopfzeile: Rand erst, wenn tatsächlich gescrollt wird. */
  var header = document.querySelector("header");
  var onScroll = function () {
    header.classList.toggle("scrolled", window.scrollY > 8);
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* Aurora folgt dem Scrollen ein wenig: Fixiert, aber nicht starr. */
  var aurora = document.querySelector(".aurora");
  if (aurora && !reduce) {
    var ticking = false;
    window.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(function () {
        var y = window.scrollY;
        aurora.style.transform = "translateY(" + (-y * 0.06) + "px)";
        ticking = false;
      });
    }, { passive: true });
  }

  /* Einblenden: sichtbar, sobald ein Abschnitt ins Bild kommt.
     Ohne JavaScript bleibt alles sichtbar (siehe .js-Schalter oben). */
  var items = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
  if (!reduce && "IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1, rootMargin: "0px 0px -8% 0px" });
    items.forEach(function (el) { io.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add("in"); });
  }
})();
