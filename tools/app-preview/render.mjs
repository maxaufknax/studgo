// Nimmt preview.html Bild für Bild auf.
//
//   node render.mjs --out <ordner>             alle Bilder als PNG (0000.png …)
//   node render.mjs --stills 2,5,9 --out <o>   nur diese Zeitpunkte (Sekunden)
//   node render.mjs --serve                    Seite unter http://localhost:8642 anbieten
//
// Weitere Schalter: --scale 2 (Pixeldichte; das Video wird später auf
// 886 × 1920 verkleinert, das glättet Kanten und Schrift), --workers 4.
//
// Gerendert wird mit dem Chromium, das Playwright mitbringt. Die Seite holt
// sich ihre Dateien über einen kleinen Server aus dem Repo, damit Symbol und
// Bildschirmfotos nicht kopiert werden müssen.

import { createServer } from "node:http";
import { readFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const PAGE = "/tools/app-preview/preview.html";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};
const has = name => args.includes(`--${name}`);

const timeline = JSON.parse(await readFile(path.join(HERE, "timeline.json"), "utf8"));

const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".json": "application/json",
  ".png": "image/png", ".webp": "image/webp",
};

function serve(port) {
  const server = createServer(async (req, res) => {
    const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
    if (url === "/tools/app-preview/timeline.js") {
      res.writeHead(200, { "content-type": TYPES[".js"] });
      return res.end(`window.TIMELINE = ${JSON.stringify(timeline)};`);
    }
    const file = path.join(ROOT, url);
    if (!file.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
    try {
      const body = await readFile(file);
      res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" });
      res.end(body);
    } catch {
      res.writeHead(404); res.end();
    }
  });
  return new Promise(resolve => server.listen(port, "127.0.0.1", () => resolve(server)));
}

function loadPlaywright() {
  const require = createRequire(import.meta.url);
  try {
    return require("playwright");
  } catch {
    const globalRoot = execSync("npm root -g").toString().trim();
    return require(path.join(globalRoot, "playwright"));
  }
}

const port = Number(opt("port", has("serve") ? 8642 : 0));
const server = await serve(port);
const base = `http://127.0.0.1:${server.address().port}`;

if (has("serve")) {
  console.log(`${base}${PAGE}?t=5  (Standbild)   ${base}${PAGE}?play  (abspielen)`);
} else {
  const out = path.resolve(opt("out", path.join(ROOT, "store/app-preview/frames")));
  await mkdir(out, { recursive: true });
  const scale = Number(opt("scale", 2));
  const workers = Number(opt("workers", 4));
  const fps = timeline.fps;
  const total = Math.round(timeline.duration * fps);

  // Je Auftrag: Dateiname und Zeitpunkt.
  const jobs = has("stills")
    ? opt("stills").split(",").map(s => ({ name: `still-${Number(s).toFixed(2)}.png`, t: Number(s) }))
    : Array.from({ length: total }, (_, i) => ({ name: `${String(i).padStart(4, "0")}.png`, t: i / fps }));

  const { chromium } = loadPlaywright();
  const started = Date.now();
  let done = 0;

  // Je Arbeiter ein eigener Browser: Ohne Grafikkarte setzt Chromium jedes
  // Bild in einem einzigen Prozess je Browser zusammen, und der wäre sonst
  // der Engpass.
  async function worker(slice) {
    const browser = await chromium.launch({ args: ["--force-color-profile=srgb", "--font-render-hinting=none"] });
    const page = await browser.newPage({ viewport: { width: 886, height: 1920 }, deviceScaleFactor: scale });
    page.on("pageerror", e => { console.error("Seitenfehler:", e.message); process.exitCode = 1; });
    await page.goto(base + PAGE);
    const info = await page.evaluate(() => window.ready);
    if (slice === 0) console.log(`Schriftgröße der Zeilen: ${info.size}px`);
    for (let j = slice; j < jobs.length; j += workers) {
      const { name, t } = jobs[j];
      await page.evaluate(t => window.renderFrame(t), t);
      await page.screenshot({ path: path.join(out, name), type: "png" });
      done++;
      if (done % 60 === 0 || done === jobs.length) {
        const s = (Date.now() - started) / 1000;
        console.log(`${done}/${jobs.length} Bilder, ${s.toFixed(0)} s`);
      }
    }
    await browser.close();
  }

  await Promise.all(Array.from({ length: Math.min(workers, jobs.length) }, (_, w) => worker(w)));
  server.close();
  console.log(`fertig: ${jobs.length} Bilder in ${out}`);
}
