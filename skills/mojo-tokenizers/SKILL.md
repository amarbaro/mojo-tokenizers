---
name: mojo-tokenizers
description: "Hugging Face tokenizer.json runtime for Mojo: byte-level BPE (GPT-2, Llama 3, Qwen), WordPiece (BERT) and Unigram (T5, XLM-R), ids equal to the Python tokenizers crate. Use to tokenize or detokenize in a Mojo program without Python at run time."
metadata:
  short-description: "Hugging Face tokenizer.json for Mojo: BPE, WordPiece and Unigram, ids match the tokenizers crate"
  owner: AMARBARO · amarbaro.org labs
  license: Apache-2.0
  origin: own
---

# mojo-tokenizers

Ids equal the Python `tokenizers` crate's on 6 real tokenizer files x 2000 generated texts; encoding is 2 to 4 times faster than the crate through Python. Mojo 1.2.

## When to use

Tokenize or detokenize with a model's own `tokenizer.json` from Mojo, no Python at run time. Not for WordLevel or other models: a model,
normalizer or pre-tokenizer outside the list in `docs/api.md` raises at load; it never mis-tokenizes.

## Install

From a clone: `mojo run -I src app.mojo`. `src/json` and `src/uregex` are vendored inside (`docs/vendored.md`); nothing else is needed.
The runnable example is `examples/quickstart.mojo` (no arguments, no files).

## The calls

| Call | What |
|---|---|
| `Tokenizer(path)` | loads a tokenizer.json; raises on an unsupported part |
| `t.encode(text) -> List[Int]` | ids; `mut self` (per-piece cache); no `[CLS]`/`[SEP]`, no truncation |
| `t.decode(ids) -> String` | text, added tokens kept; invalid UTF-8 becomes U+FFFD; raises on an id outside the vocabulary |
| `t.kind` | 0 byte-level BPE, 1 WordPiece, 2 Unigram |
| `t.tokens[id]` | id to token text (byte-level alphabet for BPE) |

## Gotchas

- `encode` equals the crate's `encode(add_special_tokens=False)`: add `[CLS]`/`[SEP]`/BOS yourself.
- An `NFC` normalizer (Qwen) is accepted but **not applied**: feed NFC text, or ids differ on decomposed input.
- BERT and Unigram normalize, so `decode(encode(x)) != x` there; byte-level BPE round-trips exactly.
- Added tokens in the text (`<|endoftext|>`, `[CLS]`) become their ids first; `lstrip`/`rstrip` absorb the white space around them (XLM-R `<mask>`); `single_word` is ignored.
- The crate fuses consecutive unknown characters into one unk id (Unigram) and keeps unassigned code points in BertNormalizer: both are matched.
- Llama 3 sets `ignore_merges`: a whole pre-token that is in the vocabulary is one id.
- Large vocabularies load as JSON first: budget tens of MB (Llama 3), about 90 MB (XLM-R).
- Mojo traps hit: a variadic `*path: String` forwarded through a helper crashed at run time; `out` is a keyword; no `Int(s, base=16)`, use `atol`.

## Gate

`scripts/check.sh` (sha256-pinned fixtures, 2000 generated texts per tokenizer against `tools/oracle.py`, API test, example),
`scripts/selfcheck.sh` (10 mutants), `scripts/bench.sh`. Run them under `systemd-run --user --scope -p MemoryMax=4G -p MemorySwapMax=0 --`.
