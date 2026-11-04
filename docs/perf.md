# Performance

`scripts/bench.sh` runs `tests/bench.mojo` and `tools/bench_oracle.py` (the `tokenizers` 0.23.3 crate through its Python binding, single thread,
`TOKENIZERS_PARALLELISM=false`) on about 1 MB of `tools/gen_texts.py` text (seed 2: prose, scripts, emoji, whitespace runs, numbers,
vocabulary entries), one `encode` call per text, 3 runs. Mojo 1.2.0, CPU, 2026-11-04.

| tokenizer | ids | Mojo encode ms | crate encode ms | Mojo load ms | crate load ms | Mojo / crate peak RSS |
|---|---|---|---|---|---|---|
| GPT-2 (whisper vocab) | 491,476 | 85 to 88 | 342 to 354 | 27 to 36 | 47 to 58 | 35 / 42 MB |
| Qwen2.5 | 425,256 | 92 to 95 (one 234) | 394 to 718 | 83 to 251 | 169 to 173 | 61 / 84 MB |
| Llama 3 | 373,268 | 76 to 81 | 311 to 327 | 115 to 122 | 211 to 226 | 76 / 109 MB |
| BERT uncased | 266,446 | 183 to 278 | 499 to 513 | 8 to 11 | 19 to 25 | 26 / 34 MB |

The crate column includes the Python call and the `Encoding` object it builds per text, so the Rust core alone is faster than shown; this is the
number a Python user gets. Ids totals are equal.

**Lines of code** (`wc -l`, excluding `src/json`, `src/uregex` and the generated `bert_tables.mojo`): `tokenizer.mojo` 533 lines, 495 non-blank.
The byte-level BPE part alone was 329 lines (306 non-blank); WordPiece added about 190. The budget was 400.

Rerun: `scripts/check.sh` once (fetches fixtures), then `scripts/bench.sh`.
