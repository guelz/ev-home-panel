#!/usr/bin/env bash
# Write the fully resolved config (all substitutions applied, lambdas included)
# of the device config to a file, for before/after diffs.
# usage: config_snapshot.sh <device-basename> <outfile>
#        config_snapshot.sh --normalize <file>   (re-sort an existing snapshot in place)
set -euo pipefail
if [[ ${1:-} == --normalize ]]; then
  python3 -I - "${2:?}" <<'PY'
import sys, yaml
class L(yaml.SafeLoader): pass
# Keep custom tags (!secret, !lambda, …) as plain "!tag value" strings.
L.add_multi_constructor('!', lambda l, tag, node:
    f"{tag} {l.construct_scalar(node)}" if isinstance(node, yaml.ScalarNode)
    else (l.construct_sequence(node) if isinstance(node, yaml.SequenceNode) else l.construct_mapping(node)))
p = sys.argv[1]
data = yaml.load(open(p, encoding='utf-8'), Loader=L)
with open(p, 'w', encoding='utf-8') as f:
    yaml.safe_dump(data, f, sort_keys=True, allow_unicode=True, width=10000, default_flow_style=False)
PY
  exit 0
fi
dev="${1:?usage: config_snapshot.sh <device-basename> <outfile>}"
out="${2:?usage: config_snapshot.sh <device-basename> <outfile>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cd "$root"
# Log lines and warnings (INFO …, "Attaching external pullup…") start with a
# capital letter, and multi-line log messages precede the YAML; esphome's
# top-level YAML keys are lowercase — start at the first one, drop the rest.
raw="$(mktemp)"; trap 'rm -f "$raw"' EXIT
set +e
esphome config "$dev.yaml" > "$raw" 2>&1
rc=$?
set -e
[[ $rc -eq 0 ]] || { cp "$raw" "$out"; echo "esphome config failed for $dev (see $out)"; exit "$rc"; }
# esphome only WARNS about an undefined substitution and leaves "${key}" in the
# config — on screen that's the raw key. Treat it as the error it is.
undef=$(grep -oE "'[A-Za-z0-9_]+' is undefined" "$raw" | sort -u || true)
if [[ -n $undef ]]; then
  echo "undefined substitution(s) in $dev:"; printf '  %s\n' "$undef"; exit 1
fi
awk '/^[a-z_]+:/{y=1} y && !/^[A-Z]/' "$raw" > "$out"
# esphome doesn't emit mapping keys in a stable order — sort them (lists keep
# their order, widget order matters) so diffs only show real changes.
"$root/scripts/config_snapshot.sh" --normalize "$out"
echo "wrote $out"
