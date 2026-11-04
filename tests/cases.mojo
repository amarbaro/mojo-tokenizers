# cases encode TOKENIZER.json TEXTS.jsonl | decode TOKENIZER.json IDS.txt | roundtrip TOKENIZER.json TEXTS.jsonl
# encode: one line of ids per text; decode: one JSON string per ids line (as tools/oracle.py prints them).
from std.sys import argv
from json import parse, Json
from tokenizers import Tokenizer


def lines(path: String) raises -> List[String]:
    var out = List[String]()
    with open(path, "r") as f:
        for l in f.read().split("\n"):
            out.append(String(l))
    _ = out.pop()  # the empty piece after the final newline
    return out^


def main() raises:
    var a = argv()
    var t = Tokenizer(String(a[2]))
    var ls = lines(String(a[3]))
    var bad = 0
    for l in ls:
        if a[1] == "decode":
            var ids = List[Int]()
            for s in l.split(" "):
                if s.byte_length() > 0:
                    ids.append(Int(s))
            print(Json.of(t.decode(ids)).dumps())
            continue
        var text = parse(l).str()
        var ids = t.encode(text)
        if a[1] == "roundtrip":
            bad += Int(t.decode(ids) != text)
            continue
        var s = String()
        for i in range(len(ids)):
            s += ("" if i == 0 else " ") + String(ids[i])
        print(s)
    if a[1] == "roundtrip":
        print("roundtrip: skip (WordPiece lowercases)" if t.wp else "roundtrip: " + String(len(ls) - bad) + "/" + String(len(ls)))
