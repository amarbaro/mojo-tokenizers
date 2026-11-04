# mojo-tokenizers

Hugging Face `tokenizer.json` runtime for Mojo: byte-level BPE (GPT-2, Llama 3, Qwen) and WordPiece (BERT). Ids are identical to the Python
`tokenizers` crate's on 4 real tokenizer files x 2000 generated texts, and encoding runs 2 to 4 times faster than the crate through Python.

```mojo
from std.sys import argv
from tokenizers import Tokenizer


def main() raises:
    var t = Tokenizer(String(argv()[1]))  # any BPE or WordPiece tokenizer.json
    var ids = t.encode("Hello, world!")
    print(len(ids), "ids:", ids[0], ids[1], "...")
    print(t.decode(ids))
```

Install: `git clone` this repo, then `mojo run -I mojo-tokenizers/src app.mojo` (Mojo 1.2). The example is `examples/quickstart.mojo`, run by the gate.

| tokenizer (encode 1 MB, ms) | Mojo | `tokenizers` crate |
|---|---|---|
| GPT-2 | 85 to 88 | 342 to 354 |
| Qwen2.5 | 92 to 95 | 394 to 718 |
| Llama 3 | 76 to 81 | 311 to 327 |
| BERT uncased | 183 to 278 | 499 to 513 |

Details: [docs/perf.md](docs/perf.md). API: [docs/api.md](docs/api.md). Design: [docs/design.md](docs/design.md).

## Not covered

Unigram (T5, XLM-R) and other models raise at load. Normalizers other than `BertNormalizer` raise; `NFC` is accepted but not applied (feed NFC
text). Truncation, padding, post-processing and added-token `lstrip`/`rstrip`/`single_word` are ignored. See the API doc.

## Checks

| Script | What |
|---|---|
| `scripts/check.sh` | per tokenizer.json in `tests/fixtures.txt` (sha256-pinned, never committed): 2000 seeded texts, ids and decodes equal to the crate, round trip for byte-level; API test; example |
| `scripts/selfcheck.sh` | 7 mutants (ignore_merges, byte alphabet, merge order, digit pattern, added tokens, strip accents, max chars) all rejected |
| `scripts/bench.sh` | the table above, 3 runs, peak RSS |
| `scripts/ci.sh` | install and gate |

Vendored: `src/json` (mojo-json), `src/uregex` (mojo-uregex), see [docs/vendored.md](docs/vendored.md). Apache-2.0.
