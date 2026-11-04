"""Hugging Face tokenizer.json runtime: byte-level BPE (GPT-2, Llama 3, Qwen). Ids equal the `tokenizers` crate's
for encode(add_special_tokens=False); decode keeps special tokens. Not implemented (raises at load): other model
types, normalizers other than NFC (NFC itself is not applied: feed NFC text), continuing_subword_prefix,
end_of_word_suffix, byte_fallback."""
from std.collections import Dict
from json import parse, Json, STR, ARR, OBJ, BOOL
from uregex import FullPattern

comptime GPT2_RE = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"
comptime CACHE_MAX = 200_000


def _text(j: Json, i: Int, key: Bool = False) -> String:
    var n = j.n[i]
    var o = n.koff if key else n.soff
    return String(unsafe_from_utf8=Span(j.buf)[Int(o) : Int(o) + Int(n.klen if key else n.slen)])


def _find(j: Json, at: Int, key: String) -> Int:
    """Node index of member `key` of the object at `at`, -1 when absent."""
    var k = at + 1
    var end = at + Int(j.n[at].size)
    while k < end:
        if _text(j, k, True) == key:
            return k
        k += Int(j.n[k].size)
    return -1


def _kind(j: Json, at: Int, key: String) -> String:
    """The "type" string of member `key` ("" when absent or null)."""
    var m = _find(j, at, key)
    return _text(j, _find(j, m, "type")) if m >= 0 and j.n[m].kind == OBJ else String()


@fieldwise_init
struct _Split(Copyable, Movable):
    var re: FullPattern
    var keep_gaps: Bool  # Isolated keeps the text between matches, Removed+invert drops it


struct Tokenizer(Movable):
    var tokens: List[String]  # id -> token text (byte-level alphabet; added tokens raw)
    var added: List[Bool]  # id -> is an added token
    var vocab: Dict[String, Int]
    var ranks: Dict[Int, Int]  # (left id << 32 | right id) -> rank << 32 | merged id
    var byte_id: List[Int]  # byte -> id of its single-character token
    var byte_str: List[String]  # byte -> that character
    var inv: List[Int]  # code point -> byte, -1 when outside the byte-level alphabet
    var splits: List[_Split]
    var prefix_space: Bool
    var ignore_merges: Bool
    var specials: List[String]  # added token texts, longest first
    var special_id: List[Int]
    var starts: List[List[Int]]  # first byte -> indexes into specials
    var cache: Dict[String, List[Int]]

    def __init__(out self, path: String) raises:
        var data: List[UInt8]
        with open(path, "r") as f:
            data = f.read_bytes()
        var j = parse(Span(data))
        var model = _find(j, 0, "model")
        if model < 0 or _kind(j, 0, "model") != "BPE":
            raise Error("tokenizers: ", path, ": only BPE models are supported, got '", _kind(j, 0, "model"), "'")
        for k in ["continuing_subword_prefix", "end_of_word_suffix"]:
            var v = _find(j, model, String(k))
            if v >= 0 and j.n[v].kind == STR and j.n[v].slen > 0:
                raise Error("tokenizers: ", path, ": ", k, " is not supported")
        var bf = _find(j, model, "byte_fallback")
        if bf >= 0 and j.n[bf].num != 0:
            raise Error("tokenizers: ", path, ": byte_fallback is not supported")
        var ig = _find(j, model, "ignore_merges")
        self.ignore_merges = ig >= 0 and j.n[ig].num != 0
        var nm = _kind(j, 0, "normalizer")
        if nm != "" and nm != "NFC":
            raise Error("tokenizers: ", path, ": normalizer ", nm, " is not supported")
        # the byte-level alphabet: printable Latin-1 as is, the other bytes shifted past 0xFF in order
        self.byte_id = List[Int](length=256, fill=-1)
        self.byte_str = List[String]()
        self.inv = List[Int](length=324, fill=-1)
        var shift = 0
        for b in range(256):
            var cp = b
            if b < 33 or (b > 126 and b < 161) or b == 173:
                cp = 256 + shift
                shift += 1
            self.inv[cp] = b
            self.byte_str.append(chr(cp))
        # vocab
        self.tokens = List[String]()
        self.added = List[Bool]()
        self.vocab = Dict[String, Int]()
        var v = _find(j, model, "vocab")
        var k = v + 1
        while k < v + Int(j.n[v].size):
            var id = Int(j.n[k].num)
            var tok = _text(j, k, True)
            while len(self.tokens) <= id:
                self.tokens.append(String())
                self.added.append(False)
            self.tokens[id] = tok.copy()
            self.vocab[tok^] = id
            k += 1
        for b in range(256):
            self.byte_id[b] = self.vocab.get(self.byte_str[b], -1)
            if self.byte_id[b] < 0:
                raise Error("tokenizers: ", path, ": not a byte-level vocabulary")
        # merges: "a b" strings or [a, b] pairs, in rank order
        self.ranks = Dict[Int, Int]()
        var m = _find(j, model, "merges")
        k = m + 1
        var rank = 0
        while k < m + Int(j.n[m].size):
            var a: String
            var b: String
            if j.n[k].kind == STR:
                var s = _text(j, k)
                var sp = s.find(" ")
                a = String(s[byte = 0 : sp]) if sp > 0 else String()
                b = String(s[byte = sp + 1 :]) if sp > 0 else String()
                k += 1
            else:
                a = _text(j, k + 1)
                b = _text(j, k + 2)
                k += 3
            var ia = self.vocab.get(a, -1)
            var ib = self.vocab.get(b, -1)
            var im = self.vocab.get(a + b, -1)
            if ia >= 0 and ib >= 0 and im >= 0:
                self.ranks[ia << 32 | ib] = rank << 32 | im
            rank += 1
        # added tokens
        self.specials = List[String]()
        self.special_id = List[Int]()
        self.starts = List[List[Int]](length=256, fill=List[Int]())
        var at = _find(j, 0, "added_tokens")
        k = at + 1
        while at >= 0 and k < at + Int(j.n[at].size):
            var id = Int(j.n[_find(j, k, "id")].num)
            var content = _text(j, _find(j, k, "content"))
            while len(self.tokens) <= id:
                self.tokens.append(String())
                self.added.append(False)
            self.tokens[id] = content.copy()
            self.added[id] = True
            var p = 0
            while p < len(self.specials) and self.specials[p].byte_length() >= content.byte_length():
                p += 1
            self.specials.insert(p, content^)
            self.special_id.insert(p, id)
            k += Int(j.n[k].size)
        for p in range(len(self.specials)):
            if self.specials[p].byte_length() > 0:
                self.starts[Int(self.specials[p].as_bytes()[0])].append(p)
        # pre-tokenizer: Split regexes, a ByteLevel with use_regex, add_prefix_space
        self.splits = List[_Split]()
        self.prefix_space = False
        var pt = _find(j, 0, "pre_tokenizer")
        if pt >= 0 and j.n[pt].kind == OBJ:
            var list = List[Int]()
            if _kind(j, 0, "pre_tokenizer") == "Sequence":
                var seq = _find(j, pt, "pretokenizers")
                var q = seq + 1
                while q < seq + Int(j.n[seq].size):
                    list.append(q)
                    q += Int(j.n[q].size)
            else:
                list.append(pt)
            for p in list:
                var ty = _text(j, _find(j, p, "type"))
                if ty == "Split":
                    var beh = _text(j, _find(j, p, "behavior"))
                    var inv = j.n[_find(j, p, "invert")].num != 0
                    if not ((beh == "Isolated" and not inv) or (beh == "Removed" and inv)):
                        raise Error("tokenizers: ", path, ": Split behavior ", beh, " invert ", inv, " is not supported")
                    var re = _find(j, _find(j, p, "pattern"), "Regex")
                    if re < 0:
                        raise Error("tokenizers: ", path, ": only Regex Split patterns are supported")
                    self.splits.append(_Split(FullPattern(_text(j, re)), beh == "Isolated"))
                elif ty == "ByteLevel":
                    self.prefix_space = j.n[_find(j, p, "add_prefix_space")].num != 0
                    if j.n[_find(j, p, "use_regex")].num != 0:
                        self.splits.append(_Split(FullPattern(GPT2_RE), True))
                else:
                    raise Error("tokenizers: ", path, ": pre-tokenizer ", ty, " is not supported")
        self.cache = Dict[String, List[Int]]()

    def encode(mut self, text: String) raises -> List[Int]:
        """Ids of `text`: added tokens are cut out first, the rest is pre-tokenized and merged."""
        var out = List[Int]()
        var b = text.as_bytes()
        var n = len(b)
        var last = 0
        var i = 0
        while i < n:
            var hit = -1
            for p in self.starts[Int(b[i])]:
                var s = self.specials[p].as_bytes()
                if i + len(s) <= n and Span(b)[i : i + len(s)] == s:
                    hit = p
                    break
            if hit < 0:
                i += 1
                continue
            self._segment(String(unsafe_from_utf8=b[last:i]), out)
            out.append(self.special_id[hit])
            i += self.specials[hit].byte_length()
            last = i
        self._segment(String(unsafe_from_utf8=b[last:n]), out)
        return out^

    def _segment(mut self, var seg: String, mut out: List[Int]) raises:
        if seg.byte_length() == 0:
            return
        if self.prefix_space and seg.as_bytes()[0] != 32:
            seg = " " + seg
        var pieces = List[String]()
        pieces.append(seg^)
        for sp in self.splits:
            var next = List[String]()
            for p in pieces:
                next.extend(sp.re.split_keep(p) if sp.keep_gaps else sp.re.findall(p))
            pieces = next^
        for p in pieces:
            self._piece(p, out)

    def _piece(mut self, piece: String, mut out: List[Int]) raises:
        if piece in self.cache:
            out.extend(Span(self.cache[piece]))
            return
        var b = piece.as_bytes()
        var n = len(b)
        var ids = List[Int](capacity=n)
        var whole = String()
        for x in b:
            ids.append(self.byte_id[Int(x)])
            if self.ignore_merges:
                whole += self.byte_str[Int(x)]
        var direct = self.vocab.get(whole, -1) if self.ignore_merges else -1
        if direct >= 0:
            ids = [direct]
        elif n > 1:
            self._merge(ids)
        if len(self.cache) >= CACHE_MAX:
            self.cache.clear()
        self.cache[piece.copy()] = ids.copy()
        out.extend(ids^)

    def _merge(self, mut ids: List[Int]) raises:
        """Lowest rank first, leftmost on ties, with a binary heap of (rank << 32 | position) and a linked list."""
        var n = len(ids)
        var nxt = List[Int](capacity=n)
        var prv = List[Int](capacity=n)
        var heap = List[Int](capacity=n)
        for i in range(n):
            nxt.append(i + 1)
            prv.append(i - 1)
        for i in range(n - 1):
            self._push(heap, ids[i], ids[i + 1], i)
        while len(heap) > 0:
            var top = heap[0]
            var last = heap.pop()
            if len(heap) > 0:
                heap[0] = last
                var i = 0
                while True:  # sift down
                    var l = 2 * i + 1
                    var s = i
                    if l < len(heap) and heap[l] < heap[s]:
                        s = l
                    if l + 1 < len(heap) and heap[l + 1] < heap[s]:
                        s = l + 1
                    if s == i:
                        break
                    heap[i], heap[s] = heap[s], heap[i]
                    i = s
            var at = top & 0xFFFFFFFF
            var q = nxt[at]
            if ids[at] < 0 or q >= n:
                continue
            var r = self.ranks.get(ids[at] << 32 | ids[q], -1)
            if r < 0 or (r >> 32) != (top >> 32):
                continue
            ids[at] = r & 0xFFFFFFFF
            ids[q] = -1
            nxt[at] = nxt[q]
            if nxt[q] < n:
                prv[nxt[q]] = at
                self._push(heap, ids[at], ids[nxt[q]], at)
            if prv[at] >= 0:
                self._push(heap, ids[prv[at]], ids[at], prv[at])
        var w = 0
        for i in range(n):
            if ids[i] >= 0:
                ids[w] = ids[i]
                w += 1
        ids.resize(w, 0)

    def _push(self, mut heap: List[Int], a: Int, b: Int, at: Int):
        var r = self.ranks.get(a << 32 | b, -1)
        if r < 0:
            return
        heap.append((r >> 32) << 32 | at)
        var i = len(heap) - 1
        while i > 0 and heap[(i - 1) // 2] > heap[i]:  # sift up
            heap[(i - 1) // 2], heap[i] = heap[i], heap[(i - 1) // 2]
            i = (i - 1) // 2

    def decode(self, ids: List[Int]) raises -> String:
        """The text of `ids`; added tokens are written as they are, invalid UTF-8 becomes U+FFFD."""
        var out = List[UInt8]()
        for id in ids:
            if id < 0 or id >= len(self.tokens):
                raise Error("tokenizers: id ", id, " is out of range")
            var tok = self.tokens[id].copy()
            var raw = self.added[id]
            var bytes = List[UInt8]()
            for c in tok.codepoints():
                var cp = Int(c)
                if cp < len(self.inv) and self.inv[cp] >= 0:
                    bytes.append(UInt8(self.inv[cp]))
                else:
                    raw = True
            if raw:
                out.extend(tok.as_bytes())
            else:
                out.extend(bytes^)
        return String(from_utf8_lossy=Span(out))
