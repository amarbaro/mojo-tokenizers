# bench TOKENIZER.json TEXTS.jsonl: load time, then encode time for every text (one call per text), ids total.
from std.sys import argv
from std.time import perf_counter_ns
from json import parse
from tokenizers import Tokenizer


def main() raises:
    var a = argv()
    var t0 = perf_counter_ns()
    var t = Tokenizer(String(a[1]))
    var t1 = perf_counter_ns()
    var texts = List[String]()
    with open(String(a[2]), "r") as f:
        for l in f.read().split("\n"):
            if l.byte_length() > 0:
                texts.append(parse(String(l)).str())
    var t2 = perf_counter_ns()
    var ids = 0
    var bytes = 0
    for x in texts:
        ids += len(t.encode(x))
        bytes += x.byte_length()
    var t3 = perf_counter_ns()
    print("load", (t1 - t0) // 1_000_000, "ms, encode", (t3 - t2) // 1_000_000, "ms,", bytes, "bytes,", ids, "ids")
