# mojo-tokenizers

<!-- badges -->
[![ci](https://github.com/amarbaro/mojo-tokenizers/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/amarbaro/mojo-tokenizers/actions/workflows/ci.yml) [![latest release](https://img.shields.io/github/v/release/amarbaro/mojo-tokenizers)](https://github.com/amarbaro/mojo-tokenizers/releases/latest) [![license](https://img.shields.io/github/license/amarbaro/mojo-tokenizers)](https://github.com/amarbaro/mojo-tokenizers/blob/main/LICENSE)
<!-- /badges -->

Hugging Face `tokenizer.json` runtime for Mojo: byte-level BPE (GPT-2, Llama 3, Qwen), WordPiece (BERT) and Unigram (T5, XLM-R). Ids are identical to the Python
`tokenizers` crate's on 6 real tokenizer files x 2000 generated texts, and encoding runs 2 to 4 times faster than the crate through Python.

Install: `pixi workspace channel add https://conda.modular.com/max https://prefix.dev/amarbaro/amarbaro`, then `pixi add mojo-tokenizers` (import `tokenizers`). From source: `git clone https://github.com/amarbaro/mojo-tokenizers`, then `mojo run -I mojo-tokenizers/src app.mojo`.
Toolchains: Mojo 1.2 stable, and the nightly 1.3.0.dev2026110805 in the weekly [mojo-libs](https://github.com/amarbaro/mojo-libs) matrix (36 libraries on stable, 35 on nightly).

```mojo
from std.os import remove
from tokenizers import Tokenizer


def main() raises:
    # A six-token WordPiece tokenizer.json written on the spot; a real one is a model's own file.
    var spec = '{"model":{"type":"WordPiece","unk_token":"[UNK]","continuing_subword_prefix":"##","max_input_chars_per_word":100,"vocab":{"[UNK]":0,"hello":1,"world":2,",":3,"!":4,"##s":5}},"normalizer":{"type":"BertNormalizer","clean_text":true,"handle_chinese_chars":true,"strip_accents":null,"lowercase":true},"pre_tokenizer":{"type":"BertPreTokenizer"},"decoder":{"type":"WordPiece","prefix":"##","cleanup":true},"added_tokens":[]}'
    with open("quickstart.json", "w") as f:
        f.write(spec)
    var t = Tokenizer("quickstart.json")
    remove("quickstart.json")
    var ids = t.encode("Hello, worlds!")
    print(len(ids), "ids:", ids[0], ids[1], ids[2], ids[3], ids[4])
    print(t.decode(ids))
```

Install: `git clone` this repo, then `mojo run -I mojo-tokenizers/src app.mojo` (Mojo 1.2). The example is `examples/quickstart.mojo`: it needs no arguments and no files, and the gate runs it.

| tokenizer (encode 1 MB, ms) | Mojo | `tokenizers` crate |
|---|---|---|
| GPT-2 | 80 to 87 | 334 to 362 |
| Qwen2.5 | 87 to 97 | 375 to 392 |
| Llama 3 | 79 to 92 | 307 to 315 |
| BERT uncased | 78 to 82 | 325 to 340 |
| T5 (Unigram) | 107 to 109 | 295 to 307 |
| XLM-R (Unigram) | 133 to 140 | 292 to 305 |

Details: [docs/perf.md](docs/perf.md). API: [docs/api.md](docs/api.md). Design: [docs/design.md](docs/design.md).

## Not covered

Other models (WordLevel, ...) raise at load, as do normalizers other than `BertNormalizer`, `Precompiled` and `Replace` (regex), and the
Unigram `prepend_scheme: first`. `NFC` is accepted but not applied (feed NFC text). Truncation, padding, post-processing and added-token
`single_word` are ignored. See the API doc.

## Checks

| Script | What |
|---|---|
| `scripts/check.sh` | per tokenizer.json in `tests/fixtures.txt` (sha256-pinned, never committed): 2000 seeded texts, ids and decodes equal to the crate, round trip for byte-level; API test; example |
| `scripts/selfcheck.sh` | 10 mutants (ignore_merges, byte alphabet, merge order, digit pattern, added tokens, strip accents, max chars, unknown fusing, charsmap grapheme rule, lstrip) all rejected |
| `scripts/bench.sh` | the table above, 3 runs, peak RSS |
| `scripts/ci.sh` | install and gate |

Vendored: `src/json` (mojo-json), `src/uregex` (mojo-uregex), see [docs/vendored.md](docs/vendored.md). Apache-2.0.
