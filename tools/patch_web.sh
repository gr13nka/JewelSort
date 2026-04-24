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
      #canvas {
        display: block; position: absolute; inset: 0;
        width: 100vw; height: 100vh;
        outline: none;
      }
      #loadingCanvas {
        position: absolute; inset: 0;
        width: 100vw; height: 100vh; background: #1a1a1f;
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
  // Loading splash until love.js finishes downloading.
  var lc = document.getElementById('loadingCanvas');
  function drawLoading(text){
    if (!lc) return;
    var dpr = window.devicePixelRatio || 1;
    lc.width = Math.floor(window.innerWidth * dpr);
    lc.height = Math.floor(window.innerHeight * dpr);
    var g = lc.getContext('2d');
    g.setTransform(dpr,0,0,dpr,0,0);
    g.fillStyle = '#1a1a1f';
    g.fillRect(0,0,window.innerWidth,window.innerHeight);
    g.fillStyle = '#e8d9b4';
    g.font = '18px sans-serif';
    g.textAlign = 'center';
    g.fillText(text, window.innerWidth/2, window.innerHeight/2);
  }
  drawLoading('Loading...');
  window.addEventListener('resize', function(){ drawLoading('Loading...'); });

  // --- Bridge state --------------------------------------------------
  var ysdk = null;
  var OUT = '/__ya_out';
  var IN  = '/__ya_in';
  var LOCALE = '/__ya_locale';

  function tryRead(path){
    try { return Module.FS.readFile(path, { encoding: 'utf8' }); }
    catch(e){ return null; }
  }
  function tryWrite(path, data){
    try { Module.FS.writeFile(path, data); return true; }
    catch(e){ console.warn('yabridge write failed', path, e); return false; }
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
      if (ysdk.features && ysdk.features.LoadingAPI) {
        try { ysdk.features.LoadingAPI.ready(); } catch(e){ console.warn(e); }
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
        tryWrite(LOCALE, String(lang));
      } catch(e){ tryWrite(LOCALE, 'en'); }
      console.info('YaGames ready, lang=', tryRead(LOCALE));
    }).catch(function(e){ console.warn('YaGames.init failed', e); });
  }

  // --- Emscripten / Love module setup --------------------------------
  window.Module = {
    arguments: ['./game.love'],
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
      if (text) { drawLoading(text); return; }
      if (Module.remainingDependencies === 0){
        document.getElementById('loadingCanvas').style.display = 'none';
        document.getElementById('canvas').style.visibility = 'visible';
        connectSdk();
        setInterval(tick, 50);
      }
    },
    totalDependencies: 0,
    remainingDependencies: 0,
    monitorRunDependencies: function(left){
      this.remainingDependencies = left;
      this.totalDependencies = Math.max(this.totalDependencies, left);
      Module.setStatus(left
        ? 'Preparing... (' + (this.totalDependencies - left) + '/' + this.totalDependencies + ')'
        : 'All downloads complete.');
    }
  };
  Module.setStatus('Downloading...');
  window.onerror = function(){
    Module.setStatus('Exception thrown, see JavaScript console');
    Module.setStatus = function(text){ if (text) Module.printErr('[post-exception] ' + text); };
  };

  // Keep the canvas sized to the viewport so the game's letterbox
  // (see src/main.lua viewport()) gets real pixel dimensions.
  function syncCanvasSize(){
    var c = document.getElementById('canvas');
    if (!c) return;
    var dpr = window.devicePixelRatio || 1;
    c.width  = Math.floor(window.innerWidth  * dpr);
    c.height = Math.floor(window.innerHeight * dpr);
    c.style.width  = window.innerWidth  + 'px';
    c.style.height = window.innerHeight + 'px';
  }
  window.addEventListener('resize', syncCanvasSize);
  syncCanvasSize();

  window.applicationLoad = function(){ Love(Module); };
})();
JS

echo "patch_web: wrote $OUT_DIR/index.html + $OUT_DIR/yabridge.js"
