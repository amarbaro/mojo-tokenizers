# Performance

`scripts/bench.sh` runs `tests/bench.mojo` and `tools/bench_oracle.py` (the `tokenizers` 0.23.3 crate through its Python binding, single thread,
`TOKENIZERS_PARALLELISM=false`) on about 1 MB of `tools/gen_texts.py` text (seed 2: prose, scripts, emoji, whitespace runs, numbers,
vocabulary entries), one `encode` call per text, 3 runs. Mojo 1.2.0, CPU, 2026-11-04. The box is shared with other lanes (load average 5 to 8), so `scripts/bench.sh` alternates the Mojo and crate runs; BERT was
re-measured against the previous binary back to back (160 ms before the Unigram rewrite, 295 ms after it, 80 ms after the ASCII fast paths).

| tokenizer | ids | Mojo encode ms | crate encode ms | Mojo load ms | crate load ms | Mojo / crate peak RSS |
|---|---|---|---|---|---|---|
| GPT-2 (whisper vocab) | 491,476 | 80 to 87 | 334 to 362 | 24 to 25 | 46 to 48 | 35 / 42 MB |
| Qwen2.5 | 425,256 | 87 to 97 | 375 to 392 | 80 to 110 | 170 | 61 / 84 MB |
| Llama 3 | 373,268 | 79 to 92 | 307 to 315 | 115 to 122 | 211 to 226 | 76 / 109 MB |
| BERT uncased | 266,446 | 78 to 82 | 325 to 340 | 7 | 13 to 14 | 26 / 34 MB |
| T5 (Unigram) | 265,947 | 107 to 109 | 295 to 307 | 13 to 14 | 36 to 41 | 28 / 56 MB |
| XLM-R (Unigram, 250k vocab) | 292,680 | 133 to 140 | 292 to 305 | 142 to 177 | 370 to 417 | 90 / 317 MB |

The crate column includes the Python call and the `Encoding` object it builds per text, so the Rust core alone is faster than shown; this is the
number a Python user gets. Ids totals are equal.

**Lines of code** (`mojo-loc`: code lines without blanks, comments and docstrings; excluding `src/json`, `src/uregex` and the generated
`bert_tables.mojo`): `tokenizer.mojo` 594. Byte-level BPE alone was 297, with WordPiece 481, with Unigram 583 before the last perf commit.
The budget was 400: not met, see the report.

Rerun: `scripts/check.sh` once (fetches fixtures), then `scripts/bench.sh`.
