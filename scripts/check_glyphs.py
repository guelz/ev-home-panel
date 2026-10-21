#!/usr/bin/env python3
"""Check a texts_<lang>.yaml before it reaches the compiler.

usage: check_glyphs.py ev-panel/texts_de.yaml        exit 0 = clean, 1 = problems

Rules (comments are read from the lines directly above a key):
  * every txt_*/glyphs_*/default_glyphs key referenced in ev-panel/ or the device
    config is defined (esphome only warns about undefined
    substitutions and then shows "${txt_x}" on screen)
  * every character of every txt_* value is in default_glyphs (newlines excepted)
  * a glyphs_* key commented "# covers: txt_a txt_b ..." contains every character
    of those texts (printf placeholders removed); if a covered text has a numeric
    placeholder, the set must also contain the digits
  * no txt_* value contains a double quote or a backslash (they break C string
    literals); a line break is only allowed in texts used solely as LVGL text:
  * every *_fmt key has "# args: %d %s ..." equal to its printf conversions in
    order (a lone "%" counts as a broken conversion), and "# max N bytes" with
    the UTF-8 length — placeholders at their worst-case width — <= N
"""
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
REF_FILES = [p for p in sorted((ROOT / "ev-panel").rglob("*.yaml")) if not p.name.startswith("texts_")] + [
    ROOT / "ev-home-panel_waveshare-p4-nano-10.1.yaml",
]
REF = re.compile(r"\$\{?((?:txt|glyphs)_[A-Za-z0-9_]+|default_glyphs)\b")
# Every printf token: "%%" or "%" + flags/width/precision + one conversion letter.
TOKEN = re.compile(r"%%|%[^a-zA-Z%]*[a-zA-Z]?")
FLOAT = re.compile(r"%[-+ 0#]*\d*\.(\d+)f")
# Worst-case printed width per placeholder; %s is the caller's (HA's) problem.
def width(tok):
    if tok.endswith(("d", "i")):
        return 11                                   # -2147483648
    if tok.endswith("u"):
        return 10
    m = FLOAT.fullmatch(tok)
    if m:
        return 6 + 1 + int(m.group(1))              # sign + 5 digits + "." + decimals
    if tok.endswith("f"):
        return 6                                    # %.0f / %f-ish
    return 0


def comments_above(lines):
    """Map key -> the comment block directly above it (joined)."""
    out, block = {}, []
    for line in lines:
        s = line.strip()
        if s.startswith("#"):
            block.append(s)
            continue
        m = re.match(r"([A-Za-z0-9_]+)\s*:", line)
        if m:
            out[m.group(1)] = " ".join(block)
        block = []
    return out


def references():
    """key -> list of (file:line, line text) where it's used (comments skipped)."""
    refs = {}
    for f in REF_FILES:
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if re.match(r"\s*(#|//)", line):
                continue
            for key in REF.findall(line):
                refs.setdefault(key, []).append((f"{f.relative_to(ROOT)}:{n}", line))
    return refs


def check(path):
    text = open(path, encoding="utf-8").read()
    data = yaml.safe_load(text) or {}
    notes = comments_above(text.splitlines())
    refs = references()
    errors = []

    for key, where in sorted(refs.items()):
        if key not in data:
            errors.append(f"undefined: {key} (used at {where[0][0]})")

    default = data.get("default_glyphs")
    if default is None:
        errors.append("default_glyphs missing")
        default = ""

    for key, val in data.items():
        val = str(val)
        # Glyph sets only go into fonts.yaml, never into C, so they may contain both.
        if key.startswith("txt_") and ('"' in val or "\\" in val):
            errors.append(f'{key}: contains " or \\ (breaks C string literals)')
        if key.startswith("txt_") and "\n" in val:
            bad = [w for w, line in refs.get(key, []) if not re.search(r"\btext:\s*\"?\$", line)]
            if bad:
                errors.append(f"{key}: line break, but used outside LVGL text: at {bad[0]} (breaks the C literal)")
        if key.startswith("txt_"):
            missing = sorted({c for c in val if c != "\n" and c not in default})
            if missing:
                errors.append(f"{key}: not in default_glyphs: {''.join(missing)!r}")
        if key.endswith("_fmt"):
            note = notes.get(key, "")
            args = re.search(r"args:\s*((?:%\S+\s*)*)", note)
            want = args.group(1).split() if args else None
            got = [t for t in TOKEN.findall(val) if t != "%%"]
            if want is None:
                errors.append(f"{key}: no '# args:' comment")
            elif want != got:
                errors.append(f"{key}: placeholders {got} != # args: {want}")
            mx = re.search(r"max\s+(\d+)\s+bytes", note)
            if not mx:
                errors.append(f"{key}: no '# max N bytes' comment")
            else:
                plain = TOKEN.sub(lambda m: "%" if m.group() == "%%" else "", val)
                need = len(plain.encode("utf-8")) + sum(width(t) for t in got)
                if need > int(mx.group(1)):
                    errors.append(f"{key}: up to {need} bytes printed > max {mx.group(1)}")

    for key, val in data.items():
        if not key.startswith("glyphs_"):
            continue
        cov = re.search(r"covers:\s*([A-Za-z0-9_ ]+)", notes.get(key, ""))
        if not cov:
            errors.append(f"{key}: no '# covers:' comment")
            continue
        for tkey in cov.group(1).split():
            if tkey not in data:
                errors.append(f"{key}: covers unknown key {tkey}")
                continue
            tval = str(data[tkey])
            toks = [t for t in TOKEN.findall(tval) if t != "%%"]
            need = set(TOKEN.sub(lambda m: "%" if m.group() == "%%" else "", tval)) - {"\n"}
            if any(width(t) and not t.endswith("s") for t in toks):
                need |= set("0123456789")
            missing = sorted(need - set(str(val)))
            if missing:
                errors.append(f"{key}: missing {''.join(missing)!r} for {tkey}")

    for e in errors:
        print(e)
    print("FAIL" if errors else "PASS", f"({len(errors)} problem(s))" if errors else "")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(check(sys.argv[1]))
