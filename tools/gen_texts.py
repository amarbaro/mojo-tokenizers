"""Seeded test texts, one JSON string per line: ASCII prose, contractions, many scripts, emoji (ZWJ, skin tones, flags),
whitespace runs, numbers, mixed lines, empty and very long inputs, and the tokenizer's own added tokens.
    gen_texts.py TOKENIZER.json N SEED > texts.jsonl
Every text is NFC (the library does not normalise). Code points come from blocks whose letter and number
classes did not change across the Unicode versions of the oracle (Rust) and uregex."""
import json, random, sys, unicodedata

tok, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rnd = random.Random(seed)
doc = json.load(open(tok))
specials = [a["content"] for a in doc["added_tokens"]]
WORDS = "the of and to in is that for it as was with be by on not he this are or his from at which but have an had they you were their one all we can her has there been if more when will would who so no".split()
RANGES = [(0xC0, 0x24F), (0x370, 0x3FF), (0x400, 0x4FF), (0x5D0, 0x5EA), (0x620, 0x64A), (0x904, 0x939), (0xE01, 0xE2E),
          (0x3041, 0x3093), (0x30A1, 0x30F6), (0x4E00, 0x9FA5), (0xAC00, 0xD7A3), (0x660, 0x669), (0x2160, 0x2188), (0xFF10, 0xFF19)]
EMOJI = [(0x1F300, 0x1F5FF), (0x1F600, 0x1F64F), (0x1F680, 0x1F6FF), (0x1F900, 0x1F9FF), (0x2600, 0x26FF), (0x2700, 0x27BF)]
WS = [" ", "\t", "\n", "\r\n", " ", "　", " ", "\n\n", "  "]
PUNCT = list("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~") + ["...", "--", "'s", "'re", "'ll", "'D", "n't", "’s", "“", "¿"]

def cp(rs): a, b = rnd.choice(rs); return chr(rnd.randint(a, b))
def ascii_(): return " ".join(rnd.choice(WORDS) for _ in range(rnd.randint(1, 30)))
def punct(): return "".join(rnd.choice(PUNCT) + rnd.choice(["", " ", rnd.choice(WORDS)]) for _ in range(rnd.randint(1, 10)))
def uni(): return "".join(cp(RANGES) if rnd.random() < .8 else " " for _ in range(rnd.randint(1, 40)))
def emoji():
    out = []
    for _ in range(rnd.randint(1, 8)):
        e = cp(EMOJI)
        r = rnd.random()
        if r < .2: e += rnd.choice("\U0001F3FB\U0001F3FC\U0001F3FD\U0001F3FE\U0001F3FF")
        elif r < .4: e += "‍" + cp(EMOJI)
        elif r < .5: e = "".join(chr(0x1F1E6 + rnd.randint(0, 25)) for _ in range(2))
        elif r < .6: e += "️"
        out.append(e + rnd.choice(["", " ", "!"]))
    return "".join(out)
def ws(): return "".join(rnd.choice(WS) * rnd.randint(1, 8) + rnd.choice(["", rnd.choice(WORDS)]) for _ in range(rnd.randint(1, 6)))
def nums(): return " ".join(rnd.choice(["", "-", "$", "#"]) + str(rnd.randint(0, 10 ** rnd.randint(1, 15))) + rnd.choice(["", ".5", ",000", "e10", "%"]) for _ in range(rnd.randint(1, 8)))
def mixed(): return "".join(rnd.choice([ascii_, punct, uni, emoji, ws, nums])() + rnd.choice(["", " ", "\n"]) for _ in range(rnd.randint(2, 6)))
def spec(): return "".join(rnd.choice([ascii_(), rnd.choice(specials), " ", "\n"]) for _ in range(rnd.randint(1, 5)))
_bs = [*range(33, 127), *range(161, 173), *range(174, 256)]
_u = {c: c for c in _bs}
_u.update({b: 256 + i for i, b in enumerate(b for b in range(256) if b not in _bs)})
_inv = {chr(c): b for b, c in _u.items()}
_uni = isinstance(doc["model"]["vocab"], list)  # Unigram: [[token, score], ...]
_vocab = [t for t, _ in doc["model"]["vocab"]] if _uni else sorted(doc["model"]["vocab"])
def word():  # the text of a random vocabulary entry (skips entries that are not whole UTF-8 characters)
    while True:
        try: return rnd.choice(_vocab).replace("\u2581", " ") if _uni else bytes(_inv[c] for c in rnd.choice(_vocab)).decode()
        except (KeyError, UnicodeDecodeError): pass
def vocab(): return "".join(word() + rnd.choice(["", " ", "\n"]) for _ in range(rnd.randint(1, 4)))
def long_(): return rnd.choice(["a", "ab", "一", " ", "1", "!!", "\U0001F600"]) * rnd.randint(200, 3000)

GEN = [ascii_] * 5 + [punct] * 2 + [uni] * 3 + [emoji] * 2 + [ws] * 3 + [nums] * 2 + [mixed] * 4 + [spec] * 2 + [vocab] * 4
fixed = ["", " ", "\n", "  hello", "hello  ", "a" * 1000, "Hello, world!", "I'm sure it's fine, they'd've gone.", "1234567890", "\U0001F468‍\U0001F469‍\U0001F467"]
for t in (fixed + [long_() for _ in range(5)] + [rnd.choice(GEN)() for _ in range(n - len(fixed) - 5)])[:n]:
    print(json.dumps(unicodedata.normalize("NFC", t)))
