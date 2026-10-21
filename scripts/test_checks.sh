#!/usr/bin/env bash
# Regression tests for the safety nets: each case builds a broken fixture from
# the real files and asserts the matching check rejects it.
# usage: test_checks.sh [--slow]   (--slow adds the esphome-config case, ~30 s)
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

expect_fail() {   # $1 = name, $2 = expected output substring, rest = command
  local name="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [[ $rc -ne 0 && $out == *"$want"* ]]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name (rc=$rc, wanted '$want')"; echo "$out" | tail -3 | sed 's/^/     /'; fi
}

texts="$root/ev-panel/texts_de.yaml"
mutate() {        # $1 = out file, $2 = key, $3 = new value (YAML double-quoted body); "" = delete key
  python3 -I - "$texts" "$1" "$2" "$3" <<'PY'
import re, sys
src, dst, key, val = sys.argv[1:]
t = open(src, encoding='utf-8').read()
pat = re.compile(r'^' + re.escape(key) + r':.*\n', re.M)
assert pat.search(t), key
t = pat.sub(lambda m: '' if val == '' else f'{key}: "{val}"\n', t)   # lambda: keep "\n" literal
open(dst, 'w', encoding='utf-8').write(t)
PY
}

# ── check_glyphs.py ──
g() { python3 -I "$root/scripts/check_glyphs.py" "$@"; }
mutate "$tmp/missing.yaml" txt_wb_error ""
expect_fail "missing text key"            "undefined: txt_wb_error" g "$tmp/missing.yaml"
mutate "$tmp/bytes.yaml" txt_wb_idle_sub_fmt "Akku %d %% — Laden heute überhaupt nicht nötig"
expect_fail "fmt too long in bytes"       "txt_wb_idle_sub_fmt: " g "$tmp/bytes.yaml"
mutate "$tmp/lone.yaml" txt_wb_unplugged_sub_fmt "Akku %d % — bitte laden"
expect_fail "lone % in fmt"               "txt_wb_unplugged_sub_fmt: placeholders" g "$tmp/lone.yaml"
mutate "$tmp/extra.yaml" txt_wb_unplugged_sub_fmt "Akku %d %i bitte laden"
expect_fail "extra conversion in fmt"     "txt_wb_unplugged_sub_fmt: placeholders" g "$tmp/extra.yaml"
mutate "$tmp/nl.yaml" txt_lock_locked "Ver\\nriegelt"
expect_fail "newline in a lambda text"    "txt_lock_locked: line break" g "$tmp/nl.yaml"
mutate "$tmp/glyph.yaml" txt_wb_idle "Warten auf Niro ✓"
expect_fail "glyph missing"               "txt_wb_idle: not in default_glyphs" g "$tmp/glyph.yaml"

# ── check_literals.sh (fixture files instead of the tree) ──
l() { "$root/scripts/check_literals.sh" --texts "$@"; }
printf '%s\n' '          lv_label_set_text(id(ci_pump), x ? "${txt_ci_pump_on}" : "Pumpe: Aus");' > "$tmp/tern.yaml"
expect_fail "ternary else literal"        "Pumpe: Aus" l "$tmp/tern.yaml"
printf '%s\n' '          lv_label_set_text(id(wb_sub),' '                            "wartet auf Start");' > "$tmp/multi.yaml"
expect_fail "multi-line label literal"    "wartet auf Start" l "$tmp/multi.yaml"
printf '%s\n' '          snprintf(b, sizeof(b), "${txt_kwh_fmt} heute", v);' > "$tmp/mixc.yaml"
expect_fail "text after subst in C"       "heute" l "$tmp/mixc.yaml"
printf '%s\n' '    - label: { text: "${txt_en_pv} Ertrag", text_font: font_label }' > "$tmp/mixy.yaml"
expect_fail "text after subst in text:"   "Ertrag" l "$tmp/mixy.yaml"

# ── config_snapshot.sh: an undefined substitution must fail ──
if [[ ${1:-} == --slow ]]; then
  mkdir -p "$tmp/repo"
  (cd "$root" && tar --exclude=.esphome --exclude=.git -cf - ev-panel scripts _fonts ev-home-panel_waveshare-p4-nano-10.1.yaml secrets.yaml) | tar -xf - -C "$tmp/repo"
  sed -i '/^  evcc_mode_now: /d' "$tmp/repo/ev-home-panel_waveshare-p4-nano-10.1.yaml"
  expect_fail "undefined substitution"    "evcc_mode_now" "$tmp/repo/scripts/config_snapshot.sh" ev-home-panel_waveshare-p4-nano-10.1 "$tmp/snap.yaml"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
