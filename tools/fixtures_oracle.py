"""Puts the tokenizer.json fixtures of tests/fixtures.txt into DIR/NAME.json (never committed): the local copy under
~/Models when its sha256 matches, else a download. Fails loudly on a checksum mismatch."""
import hashlib, os, sys, urllib.request

D = sys.argv[1]
os.makedirs(D, exist_ok=True)
for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures.txt")):
    if not line.strip() or line.startswith("#"):
        continue
    name, sha, local, url = line.split()
    src = os.path.join(os.path.expanduser("~"), "Models", local)
    data = open(src, "rb").read() if os.path.exists(src) else urllib.request.urlopen(url, timeout=60).read()
    got = hashlib.sha256(data).hexdigest()
    assert got == sha, f"{name}: sha256 {got} != {sha}"
    open(os.path.join(D, name + ".json"), "wb").write(data)
