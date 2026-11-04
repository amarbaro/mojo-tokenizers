#!/usr/bin/env bash
# Proves the gate rejects wrong code: each mutant is applied to a copy of the tree and scripts/check.sh must FAIL on it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
mutants=(
  $'src/tokenizers/tokenizer.mojo\tself.ignore_merges = ig >= 0 and j.n[ig].num != 0\tself.ignore_merges = False\tignore_merges not honoured'
  $'src/tokenizers/tokenizer.mojo\tif b < 33 or (b > 126 and b < 161) or b == 173:\tif b < 33 or (b > 126 and b < 161):\tbyte alphabet wrong'
  $'src/tokenizers/tokenizer.mojo\tand heap[l] < heap[s]:\tand heap[l] > heap[s]:\thighest rank merged first'
  $'src/tokenizers/tokenizer.mojo\t?\\\\p{N}+| ?[^\t?\\\\p{N}| ?[^\tGPT-2 pattern splits digits'
  $'src/tokenizers/tokenizer.mojo\tfor p in self.starts[Int(b[i])]:\tfor p in List[Int]():\tadded tokens not cut out'
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
