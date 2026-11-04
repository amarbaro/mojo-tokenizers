---
name: mojo-tokenizers
description: "Hugging Face tokenizer.json runtime for Mojo: byte-level BPE (GPT-2, Llama 3, Qwen) and WordPiece (BERT), ids equal to the Python tokenizers crate. Use to tokenize or detokenize in a Mojo program without Python at run time."
metadata:
  short-description: "Hugging Face tokenizer.json for Mojo: byte-level BPE and WordPiece, ids match the tokenizers crate"
---

# mojo-tokenizers

Ids equal the Python `tokenizers` crate's on real tokenizer files and generated texts. Mojo 1.2.

## When to use

Encode or decode with a model's own `tokenizer.json` from Mojo. A model, normalizer or pre-tokenizer
outside the list in `docs/api.md` raises at load; it never mis-tokenizes.

## Install

`mojo run -I src app.mojo` from a clone. `src/json` and `src/uregex` are vendored inside; nothing else is needed.

## The calls

```mojo
from std.sys import argv
from tokenizers import Tokenizer

def main() raises:
    var t = Tokenizer(String(argv()[1]))   # raises on an unsupported model, normalizer or pre-tokenizer
    var ids = t.encode("Hello, world!")    # mut self: keeps a per-piece cache
    print(len(ids), t.decode(ids))         # special tokens kept; invalid UTF-8 becomes U+FFFD
    print(t.tokens[ids[0]])                # tokens: id -> token text
```

That is the whole API (`docs/api.md`).

## Gotchas

- `encode` equals the crate's `encode(add_special_tokens=False)`: add `[CLS]`/`[SEP]`/BOS yourself; no truncation or padding.
- An `NFC` normalizer (Qwen) is accepted but **not applied**: feed NFC text, or ids differ on decomposed input.
- BERT lowercases and strips accents, so `decode(encode(x)) != x` there; byte-level BPE round-trips exactly.
- Added tokens in the text (`<|endoftext|>`, `[CLS]`) become their ids first; `lstrip`/`rstrip`/`single_word` are ignored.
- `decode` raises on an id outside the vocabulary.
- A large vocabulary file loads into memory as JSON first: budget tens of MB for Llama 3 sized files.

## Gate

`scripts/check.sh` from the repo: sha256-pinned fixtures, 2000 generated texts per tokenizer against
`tools/oracle.py`, API test, example. `scripts/selfcheck.sh` (mutants), `scripts/bench.sh`.
