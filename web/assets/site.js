/* Verhalten der Landing Page: Laufband, Kopfzeile, Lesefortschritt,
   Navigation, Einblenden, Zahlen, Telefonbühne, Rundgang, FAQ-Suche.
   Liegt als eigene Datei vor, weil die Content-Security-Policy der Seite
   keine Inline-Skripte zulässt (script-src 'self'). */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var finePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;

  var $ = function (sel, ctx) { return (ctx || document).querySelector(sel); };
  var $$ = function (sel, ctx) {
    return Array.prototype.slice.call((ctx || document).querySelectorAll(sel));
  };

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

  /* Kopfzeile, Lesefortschritt und Aurora folgen dem Scrollen - in einem
     gemeinsamen Durchlauf pro Bild, nicht drei Listener tief. */
  var header = $("header");
  var progress = $("#progress");
  var aurora = $(".aurora");
  var docEl = document.documentElement;
  var scrollTick = false;

  function onScrollFrame() {
    scrollTick = false;
    var y = window.scrollY || docEl.scrollTop;
    if (header) header.classList.toggle("scrolled", y > 8);
    if (progress) {
      var max = Math.max(0, docEl.scrollHeight - window.innerHeight);
      progress.style.transform = "scaleX(" + (max ? y / max : 0) + ")";
    }
    if (aurora && !reduce) {
      aurora.style.transform = "translateY(" + (-y * 0.06) + "px)";
    }
  }
  window.addEventListener("scroll", function () {
    if (!scrollTick) {
      scrollTick = true;
      requestAnimationFrame(onScrollFrame);
    }
  }, { passive: true });
  onScrollFrame();

  /* Einblenden: sichtbar, sobald ein Abschnitt ins Bild kommt.
     Ohne JavaScript bleibt alles sichtbar (siehe .js-Schalter oben).
     Die Schritte zeichnen dabei ihre Verbindungslinie aus. */
  var reveals = $$(".reveal");
  var stepRows = $$(".steps");
  if (!reduce && "IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1, rootMargin: "0px 0px -8% 0px" });
    reveals.forEach(function (el) { io.observe(el); });
    stepRows.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
    stepRows.forEach(function (el) { el.classList.add("in"); });
  }

  /* Aktiver Navigationspunkt: der Abschnitt, der die Bildmitte hält,
     unterstreicht seinen Link. */
  var navLinks = $$(".nav .links a[href^='#']");
  if (navLinks.length && "IntersectionObserver" in window) {
    var sectionFor = {};
    navLinks.forEach(function (a) { sectionFor[a.getAttribute("href").slice(1)] = a; });
    var navIo = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var a = sectionFor[entry.target.id];
        if (a && entry.isIntersecting) {
          navLinks.forEach(function (l) { l.classList.remove("active"); });
          a.classList.add("active");
        }
      });
    }, { rootMargin: "-40% 0px -55% 0px", threshold: 0 });
    Object.keys(sectionFor).forEach(function (id) {
      var s = document.getElementById(id);
      if (s) navIo.observe(s);
    });
  }

  /* Burger-Menü für schmale Bildschirme: öffnet, schließt bei Linkwahl,
     außerhalb und mit Escape. */
  var menuBtn = $(".menu-toggle");
  function closeMenu() {
    if (!header) return;
    header.classList.remove("menu-open");
    if (menuBtn) {
      menuBtn.setAttribute("aria-expanded", "false");
      menuBtn.setAttribute("aria-label", "Menü öffnen");
    }
  }
  if (menuBtn && header) {
    menuBtn.addEventListener("click", function () {
      var open = header.classList.toggle("menu-open");
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
      menuBtn.setAttribute("aria-label", open ? "Menü schließen" : "Menü öffnen");
    });
    $$(".mobile-panel a").forEach(function (a) {
      a.addEventListener("click", closeMenu);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") closeMenu();
    });
    document.addEventListener("pointerdown", function (e) {
      if (header.classList.contains("menu-open") &&
          !header.contains(e.target)) closeMenu();
    });
  }

  /* Zahlen in der Statikleiste zählen einmal hoch, wenn sie erscheinen. */
  function countUp(el) {
    var target = parseInt(el.getAttribute("data-count"), 10);
    var suffix = el.getAttribute("data-suffix") || "";
    if (reduce || !isFinite(target)) {
      el.textContent = target + suffix;
      return;
    }
    var start = null;
    var dur = 1100;
    var frame = function (t) {
      if (start === null) start = t;
      var p = Math.min(1, (t - start) / dur);
      p = 1 - Math.pow(1 - p, 3); /* ease-out: erst flink, dann ruhig */
      el.textContent = Math.round(target * p) + suffix;
      if (p < 1) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }
  var counters = $$("[data-count]");
  var statsBox = $(".stats");
  if (counters.length && "IntersectionObserver" in window) {
    var cio = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          counters.forEach(countUp);
          cio.disconnect();
        }
      });
    }, { threshold: 0.4 });
    cio.observe(statsBox || counters[0]);
  }

  /* Telefonbühne im Held: neigt sich ein wenig zur Maus. Nur bei feinem
     Zeiger, nie mit reduzierter Bewegung. */
  var stage = $(".stage");
  var stageInner = $(".stage-inner");
  if (stage && stageInner && finePointer && !reduce) {
    stage.addEventListener("pointermove", function (e) {
      var r = stage.getBoundingClientRect();
      var x = (e.clientX - r.left) / r.width - 0.5;
      var y = (e.clientY - r.top) / r.height - 0.5;
      stageInner.style.transform =
        "rotateX(" + (y * -6).toFixed(2) + "deg) rotateY(" + (x * 7).toFixed(2) + "deg)";
    });
    stage.addEventListener("pointerleave", function () {
      stageInner.style.transform = "";
    });
  }

  /* Lichtspur unter dem Zeiger auf Karten und Schritten: Position als
     --mx/--my, gestaffelt über requestAnimationFrame. */
  if (finePointer) {
    var spotTick = false;
    var spotLast = null;
    document.addEventListener("pointermove", function (e) {
      spotLast = e;
      if (!spotTick) {
        spotTick = true;
        requestAnimationFrame(function () {
          spotTick = false;
          if (!spotLast) return;
          var el = spotLast.target &&
            spotLast.target.closest(".card, .step, .flow");
          if (el) {
            var r = el.getBoundingClientRect();
            el.style.setProperty("--mx", ((spotLast.clientX - r.left) / r.width * 100).toFixed(1) + "%");
            el.style.setProperty("--my", ((spotLast.clientY - r.top) / r.height * 100).toFixed(1) + "%");
          }
        });
      }
    }, { passive: true });
  }

  /* Rundgang: Tabs, Pfeile und Punkte schalten Bild und Bildunterschrift.
     Läuft von selbst weiter, bis jemand eingreift; bei reduzierter Bewegung
     steht das erste Bild still. */
  var tour = $("#tour");
  if (tour) {
    var tabs = $$(".tour-tab", tour);
    var imgs = $$(".t-screen img", tour);
    var caps = $$(".tour-cap p", tour);
    var dots = $$(".tour-dot", tour);
    var idxEl = $("#tour-idx");
    var n = Math.min(tabs.length, imgs.length, caps.length, dots.length);
    var cur = 0;
    var timer = null;
    var userTouched = false;

    var show = function (i) {
      cur = (i + n) % n;
      for (var k = 0; k < n; k++) {
        tabs[k].setAttribute("aria-pressed", k === cur ? "true" : "false");
        imgs[k].classList.toggle("on", k === cur);
        caps[k].classList.toggle("on", k === cur);
        dots[k].classList.toggle("on", k === cur);
      }
      if (idxEl) idxEl.textContent = cur + 1;
    };

    var stopAuto = function () {
      userTouched = true;
      if (timer) { clearInterval(timer); timer = null; }
    };

    for (var t = 0; t < n; t++) {
      (function (k) {
        tabs[k].addEventListener("click", function () { stopAuto(); show(k); });
        dots[k].addEventListener("click", function () { stopAuto(); show(k); });
      })(t);
    }
    $$(".tour-arrow", tour).forEach(function (btn) {
      btn.addEventListener("click", function () {
        stopAuto();
        show(cur + (btn.getAttribute("data-dir") === "-1" ? -1 : 1));
      });
    });
    /* Pfeiltasten im Tabband: nächste oder vorherige Ansicht. */
    $(".tour-tabs", tour).addEventListener("keydown", function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        stopAuto();
        show(cur + (e.key === "ArrowRight" ? 1 : -1));
        tabs[cur].focus();
      }
    });

    /* Selbst laufen lassen, solange der Abschnitt im Bild und niemand
       eingegriffen hat; ein versteckter Browser-Reiter pausiert. */
    if (!reduce) {
      var startAuto = function () {
        if (timer || userTouched || document.hidden) return;
        timer = setInterval(function () { show(cur + 1); }, 6500);
      };
      var pauseAuto = function () {
        if (timer) { clearInterval(timer); timer = null; }
      };
      if ("IntersectionObserver" in window) {
        var vio = new IntersectionObserver(function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) startAuto(); else pauseAuto();
          });
        }, { threshold: 0.25 });
        vio.observe(tour);
      } else {
        startAuto();
      }
      document.addEventListener("visibilitychange", function () {
        if (document.hidden) pauseAuto(); else startAuto();
      });
      /* Zeiger über dem Telefon: lieber warten, bis wieder Ruhe ist. */
      tour.addEventListener("pointerenter", pauseAuto);
      tour.addEventListener("pointerleave", startAuto);
    }
  }

  /* FAQ-Suche: filtert die Fragen beim Tippen und zählt die Treffer.
     Ohne Treffer steht ein Hinweis mit den Auswegen. */
  var faqInput = $("#faq-q");
  var faqItems = $$(".faq details");
  var faqCount = $("#faq-count");
  var faqEmpty = $("#faq-empty");
  if (faqInput && faqItems.length) {
    var total = faqItems.length;
    var filter = function () {
      var q = faqInput.value.trim().toLowerCase();
      var hits = 0;
      faqItems.forEach(function (d) {
        var text = (d.textContent || "").toLowerCase();
        var hit = !q || text.indexOf(q) !== -1;
        d.hidden = !hit;
        if (hit) hits++;
      });
      if (faqCount) {
        faqCount.textContent = hits === total
          ? total + " Fragen"
          : hits + (hits === 1 ? " Frage" : " Fragen");
      }
      if (faqEmpty) faqEmpty.hidden = hits > 0;
    };
    faqInput.addEventListener("input", filter);
  }
})();
