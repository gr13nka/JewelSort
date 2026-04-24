#!/usr/bin/env bash
# patch_web.sh
# Post-processes the love.js build in build/web/ for Yandex Games:
#   1. Writes a full-viewport Yandex-ready index.html (no borrowed
#      <h1>/footer chrome, no <center> wrapper, CSS for touch + resize).
#   2. Writes yabridge.js — the Lua↔YaGames SDK bridge — as an
#      external file so Yandex's CSP (which has a nonce and therefore
#      disables `'unsafe-inline'` for <script> tags) still allows it
#      via `script-src 'self'`.
#
# The index.html contains zero inline scripts; Yandex's CSP header
# blocks inline scripts even though `'unsafe-inline'` is listed, because
# the CSP spec says an active nonce disables 'unsafe-inline'.
#
# Idempotent — safe to re-run.

set -u
cd "$(dirname "$0")/.."

OUT_DIR="build/web"

if [[ ! -d "$OUT_DIR" ]]; then
    echo "patch_web: $OUT_DIR does not exist. Run love.js first." >&2
    exit 1
fi
for f in index.html game.js love.js love.wasm; do
    if [[ ! -f "$OUT_DIR/$f" ]]; then
        echo "patch_web: $OUT_DIR/$f missing. Unexpected build layout." >&2
        exit 1
    fi
done

cat >"$OUT_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,shrink-to-fit=no,user-scalable=no,viewport-fit=cover">
    <title>JewelSort</title>
    <style>
      html, body {
        margin: 0; padding: 0; overflow: hidden;
        width: 100%; height: 100%;
        background: #000; color: #eee;
        font-family: -apple-system, Segoe UI, Roboto, sans-serif;
        touch-action: none;
      }
      /* Letterbox the canvas at its source 9:16 aspect: pick the
         limiting axis so the canvas element always fits the viewport
         without distortion. Canvas buffer stays at love.js's 540x960
         (from conf.lua) — CSS only scales the displayed element, which
         avoids fighting SDL_CreateWindow over the backing size. */
      #canvas {
        display: block;
        position: absolute;
        top: 50%; left: 50%;
        transform: translate(-50%, -50%);
        width:  min(100vw, calc(100vh * 9 / 16));
        height: min(100vh, calc(100vw * 16 / 9));
        outline: none;
        background: #000;
      }
      #loadingCanvas {
        position: absolute; inset: 0;
        width: 100vw; height: 100vh; background: #ece0bf;
      }
    </style>
    <!-- Yandex Games SDK. Served by Yandex when hosted on their
         platform; in local dev this 404s and the bridge falls back
         to an offline no-op mode. -->
    <script src="/sdk.js"></script>
</head>
<body>
    <canvas id="loadingCanvas" oncontextmenu="event.preventDefault()"></canvas>
    <canvas id="canvas" oncontextmenu="event.preventDefault()" tabindex="-1" style="visibility:hidden"></canvas>

    <!-- Bridge script is external (not inline) so Yandex's nonce-based
         CSP allows it via `script-src 'self'`. -->
    <script src="yabridge.js"></script>
    <script type="text/javascript" src="game.js"></script>
    <script async type="text/javascript" src="love.js" onload="applicationLoad()"></script>
</body>
</html>
HTML

cat >"$OUT_DIR/yabridge.js" <<'JS'
// yabridge.js
// Yandex Games SDK bridge for the love.js-built JewelSort. Paired with
// src/platform.lua on the Lua side. Two-file line protocol over
// Emscripten's MEMFS:
//   /__ya_out  Lua → JS commands, appended
//   /__ya_in   JS → Lua events, appended
//
// Loaded as an external file from index.html so it passes Yandex's
// strict CSP (which disables `'unsafe-inline'` when a nonce is active).

(function(){
  // --- Loading splash ------------------------------------------------
  // Animated Canvas2D scene shown until love.js/love.wasm/game.data
  // finish downloading (4-15s on Yandex). Mirrors the core mechanic:
  // a mini 3x3 board with scrambled jewels that swap themselves into
  // their matching target cells, pausing in the solved state, then
  // repeating. Palette/typography cues borrowed from src/wood.lua and
  // UI-SPEC.md so the splash reads as the same game.
  var lc = document.getElementById('loadingCanvas');
  var ctx = lc ? lc.getContext('2d') : null;

  function detectLang(){
    try {
      var q = new URLSearchParams(location.search).get('lang');
      if (q) return String(q).toLowerCase().slice(0, 2);
    } catch(e){}
    return ((navigator && navigator.language) || 'en').toLowerCase().slice(0, 2);
  }
  var LANG = detectLang();
  var STRINGS = {
    en: { loading: 'Loading…' },
    ru: { loading: 'Загрузка…' }
  };
  function t(key){
    return (STRINGS[LANG] && STRINGS[LANG][key]) || STRINGS.en[key];
  }

  // Palette — mirrors wood.palette in src/wood.lua
  var PAL = {
    parchment: '#ece0bf',
    walnut:    '#3d2a15',
    ink:       '#28180a',
    cream:     '#fff8de',
    foil:      '#efb845'
  };
  // Jewel colors (saturated — the "only-on-jewels" invariant)
  var JEWELS = [
    { fill:'#d93a4e', ring:'#8a1f30' }, // ruby
    { fill:'#3dbd76', ring:'#206a40' }, // emerald
    { fill:'#3a7fd9', ring:'#1f4c85' }, // sapphire
    { fill:'#efb845', ring:'#a57713' }  // amber (foil-matched)
  ];
  // 8 cells around a 3x3 grid (center empty), indexed clockwise from
  // top-left. Each cell's target color index into JEWELS[]:
  var BOARD_CELLS = [
    {gx:0,gy:0}, {gx:1,gy:0}, {gx:2,gy:0},
                              {gx:2,gy:1},
    {gx:2,gy:2}, {gx:1,gy:2}, {gx:0,gy:2},
    {gx:0,gy:1}
  ];
  var BOARD_TARGETS = [0,1,2,3,0,1,2,3];
  // Scramble permutation: jewel color at slot i = BOARD_TARGETS[SCRAMBLE[i]].
  // Cyclic shift by 1 gives zero fixed points against BOARD_TARGETS.
  var SCRAMBLE = [1,2,3,4,5,6,7,0];
  // Swap script: each pair (a,b) swaps jewels between those slots.
  // Four swaps restore the solved state from the scrambled state.
  var SWAPS = [[0,4],[1,5],[2,6],[3,7]];

  // Timing
  var SWAP_DURATION = 800;
  var SOLVED_HOLD   = 1200;
  var RESET_DURATION = 400;
  var CYCLE_DURATION = SWAPS.length * SWAP_DURATION + SOLVED_HOLD + RESET_DURATION;

  // Progress state (updated from monitorRunDependencies)
  var progress = { known:false, total:0, left:0 };
  var rafHandle = null;
  var reducedMotion = false;
  try { reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch(e){}

  function easeInOut(x){ return x < 0.5 ? 2*x*x : 1 - Math.pow(-2*x+2, 2)/2; }

  function dim(hex, factor){
    // Blend hex toward parchment by (1-factor)
    var r = parseInt(hex.slice(1,3),16);
    var g = parseInt(hex.slice(3,5),16);
    var b = parseInt(hex.slice(5,7),16);
    var pr = 236, pg = 224, pb = 191;
    r = Math.round(r*factor + pr*(1-factor));
    g = Math.round(g*factor + pg*(1-factor));
    b = Math.round(b*factor + pb*(1-factor));
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  function roundRect(x, y, w, h, r){
    ctx.beginPath();
    ctx.moveTo(x+r, y);
    ctx.arcTo(x+w, y,   x+w, y+h, r);
    ctx.arcTo(x+w, y+h, x,   y+h, r);
    ctx.arcTo(x,   y+h, x,   y,   r);
    ctx.arcTo(x,   y,   x+w, y,   r);
    ctx.closePath();
  }

  function resize(){
    if (!lc) return;
    var dpr = window.devicePixelRatio || 1;
    lc.width  = Math.floor(window.innerWidth  * dpr);
    lc.height = Math.floor(window.innerHeight * dpr);
  }
  resize();

  function drawJewel(cx, cy, r, jewel, lift){
    if (lift > 0.02){
      ctx.fillStyle = 'rgba(0,0,0,' + (0.15 + lift*0.25).toFixed(3) + ')';
      ctx.beginPath();
      ctx.ellipse(cx, cy + r*0.95 + lift*r*0.3, r*0.9, r*0.25, 0, 0, Math.PI*2);
      ctx.fill();
    }
    ctx.fillStyle = jewel.ring;
    ctx.beginPath();
    ctx.arc(cx, cy, r*1.08, 0, Math.PI*2);
    ctx.fill();
    ctx.fillStyle = jewel.fill;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI*2);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.32)';
    ctx.beginPath();
    ctx.arc(cx - r*0.3, cy - r*0.3, r*0.3, 0, Math.PI*2);
    ctx.fill();
  }

  function drawDemoBoard(ts, x, y, cell){
    // Compute jewel-color array for each slot at this moment.
    var scrambled = [], solved = [];
    for (var k = 0; k < 8; k++){
      scrambled[k] = BOARD_TARGETS[SCRAMBLE[k]];
      solved[k]    = BOARD_TARGETS[k];
    }
    var state = scrambled.slice();
    var activeA = -1, activeB = -1, swapT = 0;

    if (reducedMotion){
      state = solved.slice();
    } else {
      var cycleT = ts % CYCLE_DURATION;
      if (cycleT < SWAPS.length * SWAP_DURATION){
        var phase = Math.floor(cycleT / SWAP_DURATION);
        swapT = (cycleT - phase * SWAP_DURATION) / SWAP_DURATION;
        for (var s = 0; s < phase; s++){
          var tmp = state[SWAPS[s][0]];
          state[SWAPS[s][0]] = state[SWAPS[s][1]];
          state[SWAPS[s][1]] = tmp;
        }
        activeA = SWAPS[phase][0];
        activeB = SWAPS[phase][1];
      } else if (cycleT < SWAPS.length * SWAP_DURATION + SOLVED_HOLD){
        state = solved.slice();
      } else {
        state = scrambled.slice();
      }
    }

    // Draw cell tints + target rings
    for (var i = 0; i < 8; i++){
      var c = BOARD_CELLS[i];
      var cx = x + c.gx * cell + cell/2;
      var cy = y + c.gy * cell + cell/2;
      var tgt = JEWELS[BOARD_TARGETS[i]];
      ctx.fillStyle = dim(tgt.fill, 0.45);
      roundRect(cx - cell*0.42, cy - cell*0.42, cell*0.84, cell*0.84, cell*0.10);
      ctx.fill();
      ctx.strokeStyle = tgt.fill;
      ctx.lineWidth = Math.max(2, cell * 0.045);
      ctx.beginPath();
      ctx.arc(cx, cy, cell * 0.40, 0, Math.PI*2);
      ctx.stroke();
    }

    // Draw jewels (active swap pair rendered with interpolated position)
    var ease = easeInOut(swapT);
    for (var j = 0; j < 8; j++){
      var cc = BOARD_CELLS[j];
      var jx = x + cc.gx * cell + cell/2;
      var jy = y + cc.gy * cell + cell/2;
      var liftT = 0;
      if (j === activeA || j === activeB){
        var other = (j === activeA) ? activeB : activeA;
        var co = BOARD_CELLS[other];
        var ox = x + co.gx * cell + cell/2;
        var oy = y + co.gy * cell + cell/2;
        jx = jx + (ox - jx) * ease;
        jy = jy + (oy - jy) * ease;
        liftT = 4 * swapT * (1 - swapT); // 0 -> 1 -> 0
      }
      drawJewel(jx, jy - liftT * cell * 0.18, cell * 0.32, JEWELS[state[j]], liftT);
    }
  }

  function drawProgressBar(ts, x, y, w, h){
    ctx.fillStyle = PAL.walnut;
    roundRect(x, y, w, h, h/2);
    ctx.fill();
    ctx.fillStyle = 'rgba(0,0,0,0.32)';
    roundRect(x+2, y+2, w-4, h-4, Math.max(0, (h-4)/2));
    ctx.fill();
    if (progress.known && progress.total > 0){
      var pct = (progress.total - progress.left) / progress.total;
      if (pct < 0.02) pct = 0.02;
      ctx.fillStyle = PAL.foil;
      roundRect(x+2, y+2, (w-4) * pct, h-4, Math.max(0, (h-4)/2));
      ctx.fill();
    } else {
      var period = 1400;
      var phase = (ts % period) / period;
      var stripeW = w * 0.28;
      var stripeX = x + 2 + phase * (w - 4 + stripeW) - stripeW;
      ctx.save();
      roundRect(x+2, y+2, w-4, h-4, Math.max(0, (h-4)/2));
      ctx.clip();
      var grad = ctx.createLinearGradient(stripeX, 0, stripeX + stripeW, 0);
      grad.addColorStop(0,   'rgba(239,184,69,0)');
      grad.addColorStop(0.5, 'rgba(239,184,69,0.85)');
      grad.addColorStop(1,   'rgba(239,184,69,0)');
      ctx.fillStyle = grad;
      ctx.fillRect(stripeX, y+2, stripeW, h-4);
      ctx.restore();
    }
  }

  function drawFrame(ts){
    if (!ctx) return;
    var dpr = window.devicePixelRatio || 1;
    var W = window.innerWidth, H = window.innerHeight;
    // Re-sync backing store if viewport changed (resize event fires
    // before this usually, but belt-and-braces)
    if (lc.width !== Math.floor(W*dpr) || lc.height !== Math.floor(H*dpr)){
      lc.width  = Math.floor(W*dpr);
      lc.height = Math.floor(H*dpr);
    }
    ctx.setTransform(dpr,0,0,dpr,0,0);

    ctx.fillStyle = PAL.parchment;
    ctx.fillRect(0, 0, W, H);

    // Walnut frame border
    var bw = Math.max(5, Math.min(W, H) * 0.012);
    ctx.fillStyle = PAL.walnut;
    ctx.fillRect(0, 0, W, bw);
    ctx.fillRect(0, H-bw, W, bw);
    ctx.fillRect(0, 0, bw, H);
    ctx.fillRect(W-bw, 0, bw, H);

    // Title
    var titleSize = Math.min(W, H) * 0.085;
    if (titleSize < 28) titleSize = 28;
    if (titleSize > 68) titleSize = 68;
    var titleY = H * 0.16 + titleSize * 0.7;
    ctx.textAlign = 'center';
    ctx.font = '700 ' + titleSize.toFixed(0) + 'px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillStyle = 'rgba(255,248,222,0.55)';
    ctx.fillText('JewelSort', W/2, titleY + 2);
    ctx.fillStyle = PAL.foil;
    ctx.fillText('JewelSort', W/2, titleY);

    // Demo board
    var boardPx = Math.min(W * 0.72, H * 0.42);
    var cell = boardPx / 3;
    var boardX = (W - boardPx) / 2;
    var boardY = H * 0.32;
    drawDemoBoard(ts, boardX, boardY, cell);

    // Progress bar
    var pbW = Math.min(W * 0.6, 440);
    var pbH = Math.max(8, H * 0.011);
    var pbX = (W - pbW) / 2;
    var pbY = H * 0.80;
    drawProgressBar(ts, pbX, pbY, pbW, pbH);

    // Status text
    var labelSize = Math.max(14, Math.min(W, H) * 0.028);
    ctx.font = '500 ' + labelSize.toFixed(0) + 'px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillStyle = PAL.ink;
    var label = t('loading');
    if (progress.known && progress.total > 0){
      var pct = Math.round(100 * (progress.total - progress.left) / progress.total);
      label += '  ' + pct + '%';
    }
    ctx.fillText(label, W/2, pbY + pbH + labelSize * 1.6);
  }

  function rafLoop(ts){
    if (!ctx || !lc || lc.style.display === 'none'){
      rafHandle = null;
      return;
    }
    drawFrame(ts);
    rafHandle = requestAnimationFrame(rafLoop);
  }
  function startRaf(){ if (!rafHandle) rafHandle = requestAnimationFrame(rafLoop); }
  function stopRaf(){
    if (rafHandle){ cancelAnimationFrame(rafHandle); rafHandle = null; }
  }

  startRaf();
  window.addEventListener('resize', resize);

  // --- Bridge state --------------------------------------------------
  var ysdk = null;
  var OUT = '/__ya_out';
  var IN  = '/__ya_in';
  var LOCALE = '/__ya_locale';
  // Yandex covers the game iframe with its own preloader until
  // LoadingAPI.ready() fires. If we wait for love.wasm + game.data to
  // finish downloading before signaling ready, the custom splash below
  // is hidden behind Yandex's preloader for the entire wait and the
  // player never sees it. Instead we fire ready() as soon as the SDK
  // resolves so Yandex uncovers us immediately; the splash then plays
  // for the real duration of the download. loadingReadyFired guards
  // the Lua-side platform.loading_ready() dispatch from calling a
  // second time.
  var loadingReadyFired = false;

  // Emscripten + Davidobot love.js in --compatibility mode does not
  // export FS onto Module. It does, however, leak FS as a top-level
  // global inside the love.js bundle. Try both; cache the first
  // non-null resolution and log once for diagnostics.
  var _fsCached = null, _fsResolvedOnce = false;
  function getFS(){
    if (_fsCached) return _fsCached;
    var candidates = [];
    if (typeof FS !== 'undefined' && FS) candidates.push(['global FS', FS]);
    if (typeof window !== 'undefined' && window.FS) candidates.push(['window.FS', window.FS]);
    if (window.Module && window.Module.FS) candidates.push(['Module.FS', window.Module.FS]);
    for (var i = 0; i < candidates.length; i++){
      var fs = candidates[i][1];
      if (fs && typeof fs.writeFile === 'function' && typeof fs.readFile === 'function'){
        if (!_fsResolvedOnce){
          console.info('[yabridge] FS resolved via', candidates[i][0]);
          _fsResolvedOnce = true;
        }
        _fsCached = fs;
        return fs;
      }
    }
    return null;
  }

  function tryRead(path){
    var fs = getFS();
    if (!fs) return null;
    try { return fs.readFile(path, { encoding: 'utf8' }); }
    catch(e){ return null; }
  }
  function tryWrite(path, data){
    var fs = getFS();
    if (!fs){
      if (!tryWrite._warned){
        console.warn('[yabridge] no FS available — bridge calls will be dropped. path=', path);
        tryWrite._warned = true;
      }
      return false;
    }
    try { fs.writeFile(path, data); return true; }
    catch(e){ console.warn('[yabridge] write failed', path, e); return false; }
  }
  function appendIn(line){
    var prev = tryRead(IN) || '';
    tryWrite(IN, prev + line + '\n');
  }

  function parseCloudSaveLine(rest){
    // "<len> <blob...>"; <blob> is exactly <len> bytes so the protocol
    // survives newlines inside the serialized save state.
    var sp = rest.indexOf(' ');
    if (sp < 0) return null;
    var n = parseInt(rest.substring(0, sp), 10);
    if (!isFinite(n) || n < 0) return null;
    return rest.substring(sp + 1, sp + 1 + n);
  }

  function dispatch(cmd, rest){
    if (!ysdk) return;  // offline / pre-init: drop silently
    if (cmd === 'loading_ready') {
      if (loadingReadyFired) return;  // already fired from connectSdk
      if (ysdk.features && ysdk.features.LoadingAPI) {
        try { ysdk.features.LoadingAPI.ready(); loadingReadyFired = true; }
        catch(e){ console.warn(e); }
      }
    } else if (cmd === 'gameplay_start') {
      if (ysdk.features && ysdk.features.GameplayAPI) {
        try { ysdk.features.GameplayAPI.start(); } catch(e){ console.warn(e); }
      }
    } else if (cmd === 'gameplay_stop') {
      if (ysdk.features && ysdk.features.GameplayAPI) {
        try { ysdk.features.GameplayAPI.stop(); } catch(e){ console.warn(e); }
      }
    } else if (cmd === 'banner_show') {
      if (ysdk.adv && ysdk.adv.showBannerAdv) {
        try { ysdk.adv.showBannerAdv(); } catch(e){ console.warn(e); }
      }
    } else if (cmd === 'banner_hide') {
      if (ysdk.adv && ysdk.adv.hideBannerAdv) {
        try { ysdk.adv.hideBannerAdv(); } catch(e){ console.warn(e); }
      }
    } else if (cmd === 'interstitial') {
      try {
        ysdk.adv.showFullscreenAdv({
          callbacks: {
            onClose: function(wasShown){ appendIn('ad_closed ' + (wasShown ? '1' : '0')); },
            onError: function(err){ console.warn('yasdk ad error', err); appendIn('ad_error'); }
          }
        });
      } catch(e){ console.warn('yasdk interstitial threw', e); appendIn('ad_error'); }
    } else if (cmd === 'cloud_save') {
      var blob = parseCloudSaveLine(rest);
      if (blob == null) return;
      ysdk.getPlayer().then(function(p){ return p.setData({ state: blob }, true); })
        .catch(function(e){ console.warn('yasdk setData', e); });
    } else if (cmd === 'cloud_load') {
      ysdk.getPlayer().then(function(p){ return p.getData(['state']); })
        .then(function(obj){
          var blob = (obj && typeof obj.state === 'string') ? obj.state : null;
          appendIn('cloud_loaded ' + (blob != null ? blob : 'nil'));
        })
        .catch(function(e){
          console.warn('yasdk getData', e);
          appendIn('cloud_loaded nil');
        });
    }
  }

  function tick(){
    if (!window.Module || !Module.FS) return;
    var buf = tryRead(OUT);
    if (!buf) return;
    tryWrite(OUT, '');
    var lines = buf.split('\n');
    for (var i = 0; i < lines.length; i++){
      var line = lines[i];
      if (!line) continue;
      var sp = line.indexOf(' ');
      var cmd, rest;
      if (sp < 0) { cmd = line; rest = ''; }
      else { cmd = line.substring(0, sp); rest = line.substring(sp + 1); }
      dispatch(cmd, rest);
    }
  }

  function connectSdk(){
    if (typeof YaGames === 'undefined') {
      console.info('YaGames not present — running in offline mode (local dev / non-Yandex host)');
      return;
    }
    YaGames.init().then(function(sdk){
      ysdk = sdk;
      try {
        var lang = (sdk.environment && sdk.environment.i18n && sdk.environment.i18n.lang) || 'en';
        // Only overwrite /__ya_locale if Module.FS is live; during the
        // splash phase the FS may not be mounted yet, in which case
        // preRun already queued the URL-param lang.
        if (window.Module && Module.FS) tryWrite(LOCALE, String(lang));
      } catch(e){ if (window.Module && Module.FS) tryWrite(LOCALE, 'en'); }
      console.info('YaGames ready');
      // Dismiss Yandex's preloader overlay ASAP so the custom splash
      // below becomes visible. Safe to call before love.wasm finishes
      // downloading — Yandex just hides the preloader, it doesn't gate
      // anything gameplay-related.
      if (!loadingReadyFired && sdk.features && sdk.features.LoadingAPI) {
        try {
          sdk.features.LoadingAPI.ready();
          loadingReadyFired = true;
          console.info('[yabridge] LoadingAPI.ready() fired early');
        } catch(e){ console.warn('LoadingAPI.ready failed', e); }
      }
    }).catch(function(e){ console.warn('YaGames.init failed', e); });
  }

  // Kick off SDK init immediately so Yandex uncovers the iframe while
  // the splash is still animating, not after the multi-MB wasm fetch.
  connectSdk();

  // --- Emscripten / Love module setup --------------------------------
  window.Module = {
    arguments: ['./game.love'],
    // preRun fires after Emscripten's FS is mounted but before main()
    // returns, which is before Lua's love.load runs. Writing the
    // locale file here means platform.locale() sees a real value on
    // first read, instead of falling back to "en" because the
    // YaGames.init() promise hadn't resolved yet.
    preRun: [function(){
      var lang = 'en';
      try {
        var q = new URLSearchParams(location.search).get('lang');
        if (q) lang = String(q).toLowerCase().slice(0, 2);
      } catch(e){}
      // Route through getFS() fallback chain — Module.FS isn't
      // exported in this build.
      var ok = tryWrite('/__ya_locale', lang);
      if (ok) {
        console.info('[yabridge] preRun wrote locale=' + lang);
      } else {
        console.warn('[yabridge] preRun could not write locale=' + lang + ' (no FS)');
      }
    }],
    // Belt-and-suspenders hide of the splash + canvas reveal. Some
    // builds don't drive monitorRunDependencies(0) → setStatus('')
    // cleanly, so the setStatus path alone can leave #loadingCanvas
    // visible forever (shows as the splash art bleeding through the
    // letterbox gutters). onRuntimeInitialized fires deterministically
    // once the WASM runtime is up, which is always before the first
    // love.load frame renders.
    onRuntimeInitialized: function(){
      console.info('[yabridge] onRuntimeInitialized — hiding splash, revealing canvas');
      try { stopRaf(); } catch(e){}
      var lc = document.getElementById('loadingCanvas');
      if (lc) lc.style.display = 'none';
      var c = document.getElementById('canvas');
      if (c) c.style.visibility = 'visible';
      // If preRun couldn't write the locale because FS wasn't yet
      // reachable, retry now via the getFS() fallback chain.
      var have = tryRead('/__ya_locale');
      if (!have) {
        var lang = 'en';
        try {
          var q = new URLSearchParams(location.search).get('lang');
          if (q) lang = String(q).toLowerCase().slice(0, 2);
        } catch(e){}
        if (tryWrite('/__ya_locale', lang)) {
          console.info('[yabridge] onRuntimeInitialized re-wrote locale=' + lang);
        } else {
          console.warn('[yabridge] onRuntimeInitialized still no FS; locale stuck at default');
        }
      } else {
        console.info('[yabridge] onRuntimeInitialized sees locale=' + have);
      }
    },
    INITIAL_MEMORY: 67108864,
    printErr: console.error.bind(console),
    canvas: (function(){
      var c = document.getElementById('canvas');
      c.addEventListener('webglcontextlost', function(e){
        console.error('WebGL context lost; reload required');
        e.preventDefault();
      }, false);
      return c;
    })(),
    setStatus: function(text){
      if (text) {
        // Keep the rAF splash running; progress is driven separately
        // via monitorRunDependencies. Text is logged for debugging only
        // (the splash shows a localized label, not the raw Emscripten
        // status, to avoid untranslated English on Russian-locale users).
        startRaf();
        return;
      }
      if (Module.remainingDependencies === 0){
        stopRaf();
        document.getElementById('loadingCanvas').style.display = 'none';
        document.getElementById('canvas').style.visibility = 'visible';
        // SDK was connected at script start; now start polling Lua
        // commands. Idempotent-safe to enter this branch more than
        // once because setInterval is guarded by remainingDependencies.
        setInterval(tick, 50);
      }
    },
    totalDependencies: 0,
    remainingDependencies: 0,
    monitorRunDependencies: function(left){
      this.remainingDependencies = left;
      this.totalDependencies = Math.max(this.totalDependencies, left);
      progress.known = true;
      progress.total = this.totalDependencies;
      progress.left  = left;
      if (left === 0) Module.setStatus('');
    }
  };
  Module.setStatus('Downloading...');
  window.onerror = function(msg){
    console.error('[loader] exception thrown, see console:', msg);
  };

  // We used to mutate canvas.width/height to the viewport size on
  // load + every resize, but love.js's SDL_CreateWindow overwrites
  // that back to conf.lua's 540x960, so the backing buffer always
  // ended up 540x960 while CSS stretched it non-uniformly. The CSS
  // letterbox in index.html now handles aspect-preserving fit
  // without needing the buffer size to track the viewport.

  window.applicationLoad = function(){ Love(Module); };
})();
JS

echo "patch_web: wrote $OUT_DIR/index.html + $OUT_DIR/yabridge.js"
