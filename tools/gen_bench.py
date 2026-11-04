"""A ~1 MB encode benchmark input: tools/gen_texts.py texts (seed 2) until 1,000,000 bytes of text. One JSON string per line.
    gen_bench.py TOKENIZER.json > bench.jsonl"""
import json, subprocess, sys, os

here = os.path.dirname(os.path.abspath(__file__))
out, size, n = [], 0, 4000
while size < 1_000_000:
    for line in subprocess.run([sys.executable, os.path.join(here, "gen_texts.py"), sys.argv[1], str(n), "2"], capture_output=True, text=True, check=True).stdout.splitlines():
        if size >= 1_000_000: break
        out.append(line); size += len(json.loads(line).encode())
    n *= 2
print("\n".join(out))
