"""The crate's side of tests/bench.mojo: same input, one encode call per text, single thread."""
import json, os, sys, time
os.environ["TOKENIZERS_PARALLELISM"] = "false"
from tokenizers import Tokenizer

t0 = time.perf_counter()
t = Tokenizer.from_file(sys.argv[1])
t1 = time.perf_counter()
texts = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
t2 = time.perf_counter()
ids = sum(len(t.encode(x, add_special_tokens=False).ids) for x in texts)
t3 = time.perf_counter()
print("load %d ms, encode %d ms, %d bytes, %d ids" % ((t1 - t0) * 1000, (t3 - t2) * 1000, sum(len(x.encode()) for x in texts), ids))
