#!/usr/bin/env bash
# Proves the gate rejects wrong code: each mutant is applied to a copy of the tree and scripts/check.sh must FAIL on it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
mutants=(
  $'src/tokenizers/tokenizer.mojo\tself.ignore_merges = _n(j, _at(j, 0, "model/ignore_merges")) != 0\tself.ignore_merges = False\tignore_merges not honoured'
  $'src/tokenizers/tokenizer.mojo\tif b < 33 or (b > 126 and b < 161) or b == 173:\tif b < 33 or (b > 126 and b < 161):\tbyte alphabet wrong'
  $'src/tokenizers/tokenizer.mojo\tand heap[c] < heap[s]:\tand heap[c] > heap[s]:\thighest rank merged first'
  $'src/tokenizers/tokenizer.mojo\t?\\\\p{N}+| ?[^\t?\\\\p{N}| ?[^\tGPT-2 pattern splits digits'
  $'src/tokenizers/tokenizer.mojo\tfor p in range(len(self.specials)):\tfor p in range(0):\tadded tokens not cut out'
  $'src/tokenizers/tokenizer.mojo\telif self.norm & 4 != 0 and _in(MARKS, cp):\telif False and _in(MARKS, cp):\tstrip_accents not applied'
  $'src/tokenizers/tokenizer.mojo\tself.max_chars = _n(j, _at(j, model, "max_input_chars_per_word"))\tself.max_chars = 100000\tmax_input_chars_per_word ignored'
  $'src/tokenizers/tokenizer.mojo\tif tid[e] != self.unk or len(ids) == 0 or ids[len(ids) - 1] != self.unk:\tif True:\tconsecutive unknowns not fused'
  $'src/tokenizers/tokenizer.mojo\tg.byte_length() < 6\tg.byte_length() < 0\twhole-grapheme charsmap lookup dropped'
  $'src/tokenizers/tokenizer.mojo\tself._seg(_trim(seg, False) if self.spf[hit] & 1 != 0 else seg^, out, rs)\tself._seg(seg^, out, rs)\tadded-token lstrip ignored'
)
for m in "${mutants[@]}"; do
  IFS=$'\t' read -r file from to why <<< "$m"
  d=$ROOT/.work/mutant; rm -rf "$d"; mkdir -p "$d/.work"
  cp -r src tests tools scripts "$d"; ln -s "$ROOT/.venv" "$d/.venv"
  python3 -I -c 'import sys; p,a,b=sys.argv[1:]; s=open(p).read(); assert a in s, "mutant does not apply: "+a; open(p,"w").write(s.replace(a,b,1))' "$d/$file" "$from" "$to" \
    || { echo "FAIL selfcheck: mutant does not apply ($why)"; exit 1; }
  if "$d/scripts/check.sh" > "$d.log" 2>&1; then echo "FAIL selfcheck: gate passed a mutant ($why)"; exit 1; fi
  echo "selfcheck: rejected ($why): $(grep -m1 FAIL "$d.log")"
done
echo "PASS selfcheck"
