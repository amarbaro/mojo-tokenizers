#!/usr/bin/env bash
# The gate. For each tokenizer.json in tests/fixtures.txt and 2000 seeded texts (tools/gen_texts.py): $CASES encode must
# print the ids the `tokenizers` crate prints (tools/oracle.py), $CASES decode must print what the crate decodes those
# ids to, and decode(encode(text)) must give the text back. Then the API test and the example.
# CASES="uv run python -I tools/oracle.py" proves the gate with the oracle as its own stand-in (no roundtrip then).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
M=.venv/bin/mojo
P=.venv/bin/python
CASES=${CASES:-.work/cases}
N=${N:-2000}
if [[ $CASES == .work/cases ]]; then
  $M build -I src tests/cases.mojo -o .work/cases 2>.work/build.err || { echo "FAIL build: tests/cases.mojo"; cat .work/build.err; exit 1; }
fi
F=.work/fx
$P tools/fixtures_oracle.py $F || { echo "FAIL setup: fixtures"; exit 1; }
nt=0; ni=0
for name in $(awk '!/^#/ && NF {print $1}' tests/fixtures.txt); do
  $P tools/gen_texts.py $F/$name.json "$N" 1 > $F/$name.texts || { echo "FAIL setup: gen_texts $name"; exit 1; }
  $P -I tools/oracle.py encode $F/$name.json $F/$name.texts > $F/$name.ref.ids
  $CASES encode $F/$name.json $F/$name.texts > $F/$name.got.ids || { echo "FAIL encode: $name crashed"; exit 1; }
  cmp -s $F/$name.ref.ids $F/$name.got.ids || {
    echo "FAIL oracle: encode $name differs from the crate"
    paste -d'|' $F/$name.texts $F/$name.ref.ids $F/$name.got.ids | awk -F'|' '$2 != $3 {print "  text " $1; print "  want " $2; print "  got  " $3; if (++n == 2) exit}' | cut -c1-300
    exit 1; }
  ni=$((ni + $(wc -l < $F/$name.got.ids)))
  $P -I tools/oracle.py decode $F/$name.json $F/$name.ref.ids > $F/$name.ref.dec
  $CASES decode $F/$name.json $F/$name.ref.ids > $F/$name.got.dec || { echo "FAIL decode: $name crashed"; exit 1; }
  cmp -s $F/$name.ref.dec $F/$name.got.dec || { echo "FAIL oracle: decode $name differs from the crate"; exit 1; }
  if [[ $CASES == .work/cases ]]; then
    [[ $($CASES roundtrip $F/$name.json $F/$name.texts) == "roundtrip: $N/$N" ]] || { echo "FAIL roundtrip: $name"; $CASES roundtrip $F/$name.json $F/$name.texts; exit 1; }
  fi
  nt=$((nt + 1))
done
echo "oracle: $nt tokenizers, $ni texts: ids and decodes identical to the crate"
echo "PASS all"
