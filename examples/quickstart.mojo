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
