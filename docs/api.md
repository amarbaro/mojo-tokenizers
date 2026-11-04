# API

`from tokenizers import Tokenizer`. Everything here is asserted in `tests/api.mojo` or compared with the `tokenizers` crate by `scripts/check.sh`.

| Call | Behaviour | Raises |
|---|---|---|
| `Tokenizer(path)` | Loads a Hugging Face `tokenizer.json`: BPE with a byte-level alphabet (GPT-2, Llama 3, Qwen) or WordPiece with `BertNormalizer` (BERT). | Unreadable or invalid JSON; a model other than BPE or WordPiece (Unigram); another normalizer or pre-tokenizer; `continuing_subword_prefix`, `end_of_word_suffix` or `byte_fallback` on a BPE model; a vocabulary without the 256 byte tokens. |
| `encode(mut self, text) -> List[Int]` | Ids of `text`, as the crate's `encode(add_special_tokens=False)`. Added tokens found in the text become their ids first. No `[CLS]`/`[SEP]`, truncation or padding. | Never on valid input. |
| `decode(self, ids) -> String` | Text of `ids`, special tokens included (the crate's `skip_special_tokens=False`). Byte-level: invalid UTF-8 becomes U+FFFD. WordPiece: tokens joined with spaces, `##` joined, the crate's `cleanup`. | An id outside the vocabulary. |
| `wp: Bool` | True for a WordPiece tokenizer. | |
| `tokens: List[String]` | Id to token text (byte-level alphabet for BPE). | |

`encode` takes `mut self` because it keeps a per-piece cache (at most 200,000 entries, then cleared).

## Not covered (raises at load, never mis-tokenizes)

Unigram (T5, XLM-R), other normalizers (Lowercase, NFD, Precompiled, Replace, ...), Split behaviors other than Isolated and Removed+invert,
`lstrip`/`rstrip`/`single_word` on added tokens (ignored), `add_special_tokens=True` post-processing, truncation and padding (ignored).
An `NFC` normalizer is accepted but not applied: feed NFC text (the gate texts are NFC).
