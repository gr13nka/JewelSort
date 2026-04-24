#!/usr/bin/env bash
# Repo invariants for JewelSort. Run from any directory:
#   ./tools/check.sh
#
# Exits non-zero if any invariant fails. Safe to run after any code edit;
# kept cheap (<1s) so it can be wired into a pre-commit hook if desired.
#
# What's checked:
#   1. No `goto` statements outside comments in any .lua file (love.js has
#      broken goto support via Fengari — see CLAUDE.md).
#   2. No banned runtime APIs: os.execute, io.popen, love.thread, FFI.
#   3. Optional `luac -p` syntax check on every .lua file when luac or a
#      compatible `lua -c` shim is available. Skipped with a warning when
#      no local Lua is installed.
#   4. All level PNGs are readable and have at least one opaque pixel
#      (loader would otherwise silently skip them).

set -u
cd "$(dirname "$0")/.."

red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'; dim=$'\033[2m'; reset=$'\033[0m'
fail=0
pass_count=0
fail_count=0

pass() { printf "%s  OK   %s %s\n" "$green" "$reset" "$1"; pass_count=$((pass_count+1)); }
warn() { printf "%s  WARN %s %s\n" "$yellow" "$reset" "$1"; }
bad()  { printf "%s  FAIL %s %s\n" "$red"   "$reset" "$1"; fail=1; fail_count=$((fail_count+1)); }

# 1. goto check. Allow `goto` inside line comments (-- ...) but nowhere else.
goto_hits=$(grep -rn --include='*.lua' -E '(^|[^-])goto[[:space:]]' . \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' || true)
if [[ -z "$goto_hits" ]]; then
    pass "no goto statements in .lua (outside comments)"
else
    bad  "goto statement found outside comments:"
    printf "%s\n" "$goto_hits" | sed 's/^/       /'
fi

# 2. Banned APIs.
banned='os\.execute|io\.popen|love\.thread|require\(["'\'']ffi["'\'']\)'
api_hits=$(grep -rnE --include='*.lua' "$banned" . \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' \
    | grep -vE '/tools/check\.sh' || true)
if [[ -z "$api_hits" ]]; then
    pass "no banned runtime APIs (os.execute/io.popen/love.thread/ffi)"
else
    bad  "banned API reference found:"
    printf "%s\n" "$api_hits" | sed 's/^/       /'
fi

# 3. Optional syntax check.
lua_bin=""
for cand in luac5.4 luac5.3 luac5.1 luac lua5.4 lua5.3 lua5.1 lua; do
    if command -v "$cand" >/dev/null 2>&1; then lua_bin="$cand"; break; fi
done
if [[ -z "$lua_bin" ]]; then
    warn "no luac/lua in PATH — skipping syntax check"
else
    syntax_fail=0
    while IFS= read -r -d '' f; do
        if [[ "$lua_bin" == luac* ]]; then
            out=$("$lua_bin" -p "$f" 2>&1) || { bad "syntax: $f"; printf "%s\n" "$out" | sed 's/^/       /'; syntax_fail=1; }
        else
            out=$("$lua_bin" -e "loadfile('$f') or error('parse')" 2>&1) \
                || { bad "syntax: $f"; printf "%s\n" "$out" | sed 's/^/       /'; syntax_fail=1; }
        fi
    done < <(find . -name '*.lua' -not -path './build/*' -print0)
    (( syntax_fail == 0 )) && pass "lua syntax clean ($lua_bin)"
fi

# 4. Level PNG sanity.
if command -v python3 >/dev/null 2>&1; then
    png_report=$(python3 - <<'PY'
import sys, os
try:
    from PIL import Image
except Exception as e:
    print("SKIP", e); sys.exit(0)
bad = []
empty = []
n = 0
for root, _, files in os.walk('levels'):
    for name in files:
        if not name.lower().endswith('.png'): continue
        p = os.path.join(root, name); n += 1
        try:
            img = Image.open(p).convert('RGBA')
        except Exception as e:
            bad.append(f"{p}: {e}"); continue
        w,h = img.size
        has = False
        for y in range(h):
            for x in range(w):
                if img.getpixel((x,y))[3] > 0:
                    has = True; break
            if has: break
        if not has:
            empty.append(p)
print(f"OK {n}")
for p in bad:   print("BAD", p)
for p in empty: print("EMPTY", p)
PY
)
    if [[ "$png_report" == SKIP* ]]; then
        warn "PIL unavailable — skipping PNG sanity (${png_report#SKIP })"
    else
        if ! grep -qE '^(BAD|EMPTY)' <<< "$png_report"; then
            count=$(awk '/^OK/ {print $2}' <<< "$png_report")
            pass "level PNGs readable with opaque pixels ($count)"
        else
            bad "level PNG problems:"
            grep -E '^(BAD|EMPTY)' <<< "$png_report" | sed 's/^/       /'
        fi
    fi
else
    warn "python3 unavailable — skipping PNG sanity"
fi

printf "\n"
if (( fail == 0 )); then
    printf "%s%d passed%s\n" "$green" "$pass_count" "$reset"
    exit 0
else
    printf "%s%d failed, %d passed%s\n" "$red" "$fail_count" "$pass_count" "$reset"
    exit 1
fi
