"""Oracle: Hugging Face `tokenizers`, single-thread. Same operations as tests/cases.mojo.
    oracle.py encode TOKENIZER.json TEXTS.jsonl   -> one line of space-separated ids per text
    oracle.py decode TOKENIZER.json IDS.txt       -> one JSON string per ids line (special tokens kept)
Run with the dev group: uv run python -I tools/oracle.py ..."""
import json, sys
from tokenizers import Tokenizer

op, tok, path = sys.argv[1:4]
t = Tokenizer.from_file(tok)
for line in open(path, encoding="utf-8"):
    if op == "encode":
        print(" ".join(map(str, t.encode(json.loads(line), add_special_tokens=False).ids)))
    else:
        print(json.dumps(t.decode([int(x) for x in line.split()], skip_special_tokens=False)))
