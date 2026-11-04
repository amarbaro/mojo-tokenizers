# Asserts what README.md and docs/api.md say, on .work/fx/{gpt2,bert,...}.json (scripts/check.sh fetches them).
from std.testing import assert_equal, assert_true, assert_raises
from tokenizers import Tokenizer


def ids_of(mut t: Tokenizer, s: String) raises -> String:
    var out = String()
    for i in t.encode(s):
        out += ("" if out.byte_length() == 0 else " ") + String(i)
    return out^


def main() raises:
    var g = Tokenizer(".work/fx/gpt2.json")
    assert_equal(ids_of(g, "Hello, world!"), "15947 11 1002 0")
    assert_equal(ids_of(g, "Hello, world!<|endoftext|>"), "15947 11 1002 0 50257")  # added tokens are cut out first
    assert_equal(ids_of(g, ""), "")
    assert_equal(g.decode(g.encode("Hello, world!<|endoftext|>")), "Hello, world!<|endoftext|>")
    assert_equal(g.decode(g.encode("café \U0001F600")), "café \U0001F600")  # byte-level: any text round-trips
    var b = Tokenizer(".work/fx/bert.json")
    assert_equal(ids_of(b, "Hello, Wörld! naïve"), "7592 1010 2088 999 15743")  # lowercased, accents stripped
    assert_equal(b.decode(b.encode("Hello, Wörld! naïve")), "hello, world! naive")
    assert_equal(ids_of(b, "[CLS] hi"), "101 7632")
    with open(".work/fx/unigram.json", "w") as f:
        f.write('{"model":{"type":"Unigram","vocab":[["a",0.0]]},"added_tokens":[]}')
    with assert_raises(contains="only BPE and WordPiece"):  # Unigram is not implemented: raises at load, never mis-tokenizes
        _ = Tokenizer(".work/fx/unigram.json")
    print("api: ok")
