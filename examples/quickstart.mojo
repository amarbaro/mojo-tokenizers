from std.sys import argv
from tokenizers import Tokenizer


def main() raises:
    var t = Tokenizer(String(argv()[1]))  # any BPE or WordPiece tokenizer.json
    var ids = t.encode("Hello, world!")
    print(len(ids), "ids:", ids[0], ids[1], "...")
    print(t.decode(ids))
