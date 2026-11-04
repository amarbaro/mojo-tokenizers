#!/usr/bin/env bash
# tests/bench.mojo vs tools/bench_oracle.py (the tokenizers crate, single thread) on ~1 MB of tools/gen_texts.py text per
# tokenizer, 3 runs each: each prints its own timed work in ms; peak RSS of the whole process from getrusage.
# Run scripts/check.sh once first (it fetches the tokenizer.json fixtures).
set -euo pipefail
cd "$(dirname "$0")/.."
.venv/bin/mojo build -I src tests/bench.mojo -o .work/bench 2>.work/build.err || { echo "FAIL build: tests/bench.mojo"; cat .work/build.err; exit 1; }
run() {
  .venv/bin/python -I -c 'import resource, subprocess, sys
out = subprocess.run(sys.argv[2:], capture_output=True, text=True, check=True).stdout.strip()
print("%-7s %s, peak RSS %d MB" % (sys.argv[1], out, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024))' "$@" \
    || { echo "FAIL run: $1"; exit 1; }
}
for name in $(awk '!/^#/ && NF {print $1}' tests/fixtures.txt); do
  F=.work/fx/$name; [[ -f $F.json ]] || { echo "FAIL setup: $F.json missing (run scripts/check.sh first)"; exit 1; }
  .venv/bin/python tools/gen_bench.py $F.json > $F.bench.jsonl
  echo "== $name"
  for i in 1 2 3; do run mojo .work/bench $F.json $F.bench.jsonl; run crate .venv/bin/python -I tools/bench_oracle.py $F.json $F.bench.jsonl; done
done
