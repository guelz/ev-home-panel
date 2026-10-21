#!/usr/bin/env bash
# Fail if an HA entity or a user-visible text is still a literal instead of a
# substitution. usage: check_literals.sh [--entities|--texts] [path ...]
# Default paths: ev-panel/ and the device config. Lines containing
# "i18n-ok" are documented exceptions and skipped; YAML (#) and C++ (//) comment
# lines are ignored. texts_*.yaml is where texts belong, so it is not scanned.
set -uo pipefail
cd "$(dirname "$0")/.."

mode=all
[[ ${1:-} == --entities || ${1:-} == --texts ]] && { mode=$1; shift; }
if [[ $# -gt 0 ]]; then FILES=("$@")
else FILES=(ev-panel ev-home-panel_waveshare-p4-nano-10.1.yaml); fi
L='[A-Za-zÄÖÜäöü]'

# Every scanned line, with a string literal that is EXACTLY one substitution
# ("${txt_x}" / "$txt_x") blanked to "" first — so "${a} heute" still has letters.
lines() {
  find "${FILES[@]}" -name '*.yaml' ! -name 'texts_*.yaml' -print0 | sort -z |
  while IFS= read -r -d '' f; do
    sed -E 's/"\$\{?[A-Za-z0-9_]+\}?"/""/g' "$f" | grep -nv 'i18n-ok' | sed "s|^|$f:|"
  done | grep -vE '^[^:]+:[0-9]+: *(#|//)'
}
scan() {   # $1 = label, $2 = ERE
  printf '%s\n' "$all" | grep -E -- "$2" | sed "s|^|[$1] |"
}

all=$(lines)
out=""
if [[ $mode == all || $mode == --entities ]]; then
  out+=$(scan entity '(^|[^a-z_])(entity_id|entity): *"?[a-z_]+\.[a-z0-9_]+')$'\n'
fi
if [[ $mode == all || $mode == --texts ]]; then
  out+=$(scan text   "(^|[^a-z_])text: *\"[^\"]*$L")$'\n'
  out+=$(scan text   "(^|[^a-z_])text: *$L")$'\n'
  out+=$(scan label  "lv_label_set_text\([^,]+, *\"[^\"]*$L")$'\n'
  out+=$(scan format "snprintf\([^\"]*\"[^\"]*$L{2}")$'\n'
  out+=$(scan assign "[^=!<>]= *\"[^\"]*$L{2}")$'\n'
  out+=$(scan tern   "\? *\"[^\"]*$L{2}[^\"]*\" *:")$'\n'
  out+=$(scan tern   "\? *\"[^\"]*\" *: *\"[^\"]*$L{2}")$'\n'
  out+=$(scan array  "\{ *\"[^\"]*$L{2}")$'\n'
  out+=$(scan return "return *\"[^\"]*$L{2}")$'\n'
  # A literal alone on a continuation line, e.g. the 2nd line of a wrapped call.
  out+=$(scan cont   "^[^:]+:[0-9]+: *\"[^\"]*$L{2}[^\"]*\" *[,)]")$'\n'
fi

out=$(printf '%s' "$out" | sed '/^$/d' | sort -u)
if [[ -n $out ]]; then
  printf '%s\n' "$out"
  echo "FAIL: $(printf '%s\n' "$out" | wc -l) literal(s)"
  exit 1
fi
echo "PASS: no literals"
