"""Hugging Face tokenizer.json runtime: byte-level BPE (GPT-2, Llama 3, Qwen), WordPiece with BertNormalizer (BERT) and
Unigram with a Precompiled normalizer and Metaspace (T5, XLM-R). Ids equal the `tokenizers` crate's for
encode(add_special_tokens=False). Unsupported parts raise at load. An NFC normalizer is not applied: feed NFC text."""
from std.base64 import b64decode
from std.collections import Dict
from std.memory import bitcast
from json import parse, Json, STR, OBJ
from uregex import FullPattern
from .bert_tables import CONTROL, PUNCT, MARKS, SPACE, CJK, STRIP, LOWER, STRIPLOWER

comptime GPT2_RE = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"
comptime SP = "▁"


def _s(j: Json, i: Int, key: Bool = False) -> String:
    """The text of node i (its member name when key), "" when absent or not a string."""
    if i < 0 or (not key and j.n[i].kind != STR):
        return String()
    var n = j.n[i]
    var o = Int(n.koff if key else n.soff)
    return String(unsafe_from_utf8=Span(j.buf)[o : o + Int(n.klen if key else n.slen)])


def _at(j: Json, at: Int, path: String) -> Int:
    """Node index of the member reached through `path` ("a/b") from the object at `at`, -1 when absent."""
    var a = at
    for key in path.split("/"):
        var k = a + 1 if a >= 0 and j.n[a].kind == OBJ else -1
        while k >= 0 and k < a + Int(j.n[a].size) and _s(j, k, True) != key:
            k += Int(j.n[k].size)
        a = k if k >= 0 and k < a + Int(j.n[a].size) else -1
    return a


def _n(j: Json, i: Int) -> Int:
    return Int(j.n[i].num) if i >= 0 else 0


def _list(j: Json, at: Int, key: String, list: String) -> List[Int]:
    """The node itself, or the members of its `list` when it is a Sequence."""
    var out = List[Int]()
    var a = _at(j, at, key)
    if a < 0 or j.n[a].kind != OBJ:
        return out^
    var seq = _at(j, a, list) if _s(j, _at(j, a, "type")) == "Sequence" else -1
    var k = seq + 1 if seq >= 0 else a
    while seq < 0 or k < seq + Int(j.n[seq].size):
        out.append(k)
        if seq < 0:
            break
        k += Int(j.n[k].size)
    return out^


def _in(ranges: StaticString, cp: Int) -> Bool:
    """cp in a sorted table of 12-hex-digit (first, last) ranges."""
    var b = ranges.as_bytes()
    var lo = 0
    var hi = len(b) // 12
    while lo < hi:
        var mid = (lo + hi) // 2
        if _hex(b, mid * 12 + 6) < cp:
            lo = mid + 1
        else:
            hi = mid
    return lo < len(b) // 12 and _hex(b, lo * 12) <= cp


def _hex(b: Span[UInt8, _], at: Int) -> Int:
    var v = 0
    for k in range(at, at + 6):
        v = v * 16 + (Int(b[k]) - 48 if b[k] < 58 else Int(b[k]) - 87)
    return v


def _map(table: String) raises -> Dict[Int, List[Int]]:
    """`cp=cp,cp;` entries (hex) into a dict."""
    var out = Dict[Int, List[Int]]()
    for e in table.split(";"):
        var kv = e.split("=")
        if len(kv) == 2:
            var to = List[Int]()
            for c in kv[1].split(","):
                if c.byte_length() > 0:
                    to.append(atol(String(c), base=16))
            out[atol(String(kv[0]), base=16)] = to^
    return out^


def _sp(cp: Int) -> Bool:
    return cp == 32 or (cp >= 9 and cp <= 13) or (cp >= 128 and _in(SPACE, cp))


def _pu(cp: Int) -> Bool:
    return (cp >= 33 and cp <= 47) or (cp >= 58 and cp <= 64) or (cp >= 91 and cp <= 96) or (cp >= 123 and cp <= 126) or (cp >= 128 and _in(PUNCT, cp))


def _trim(s: String, left: Bool) -> String:
    """`s` without its leading (left) or trailing white space."""
    var cps = List[Int]()
    for c in s.codepoints():
        cps.append(Int(c))
    var a = 0
    var e = len(cps)
    while left and a < e and _sp(cps[a]):
        a += 1
    while not left and e > a and _sp(cps[e - 1]):
        e -= 1
    var out = List[UInt8]()
    for i in range(a, e):
        _put(out, cps[i])
    return String(unsafe_from_utf8=Span(out))


def _put(mut out: List[UInt8], cp: Int):
    if cp < 128:
        out.append(UInt8(cp))
    else:
        out.extend(chr(cp).as_bytes())


struct Tokenizer(Movable):
    var kind: Int  # 0 byte-level BPE, 1 WordPiece, 2 Unigram
    var tokens: List[String]  # id -> token text
    var added: List[Bool]  # id -> is an added token
    var vocab: Dict[String, Int]
    var specials: List[String]  # added token texts, longest first
    var spid: List[Int]
    var spf: List[Int]  # 1 lstrip, 2 rstrip: the token absorbs the white space around it
    var first: List[Bool]  # first byte of any special
    var cache: Dict[String, List[Int]]
    var unk: Int
    var strip: Bool  # decode: drop the leading space (Metaspace) / WordPiece cleanup
    # BPE
    var ranks: Dict[Int, Int]  # (left id << 32 | right id) -> rank << 32 | merged id
    var bid: List[Int]  # byte -> id of its single-character token
    var bstr: List[String]  # byte -> that character
    var inv: List[Int]  # code point -> byte, -1 outside the byte-level alphabet
    var splits: List[FullPattern]
    var ignore_merges: Bool
    # WordPiece
    var sub_prefix: String
    var max_chars: Int
    var norm: Int  # BertNormalizer: 1 clean_text, 2 handle_chinese_chars, 4 strip_accents, 8 lowercase
    var maps: Dict[Int, List[Int]]
    # Unigram
    var scores: List[Float64]
    var maxlen: Int  # longest token in characters
    var cm: List[UInt8]  # Precompiled charsmap: u32 trie size, double-array trie, replacement pool
    var subs: List[FullPattern]  # Replace normalizers
    var subw: List[String]
    var ws_split: Bool
    var prepend: Bool

    def __init__(out self, path: String) raises:
        var data: List[UInt8]
        with open(path, "r") as f:
            data = f.read_bytes()
        var j = parse(Span(data))
        var ty = _s(j, _at(j, 0, "model/type"))
        self.kind = 1 if ty == "WordPiece" else 2 if ty == "Unigram" or (ty == "" and _at(j, 0, "model/unk_id") >= 0) else 0
        if self.kind == 0 and ty != "BPE":
            raise Error("tokenizers: ", path, ": model '", ty, "' is not supported")
        self.tokens = List[String]()
        self.added = List[Bool]()
        self.vocab = Dict[String, Int]()
        self.specials = List[String]()
        self.spid = List[Int]()
        self.spf = List[Int]()
        self.first = List[Bool](length=256, fill=False)
        self.cache = Dict[String, List[Int]]()
        self.unk = -1
        self.strip = False
        self.ranks = Dict[Int, Int]()
        self.bid = List[Int](length=256, fill=-1)
        self.bstr = List[String]()
        self.inv = List[Int](length=324, fill=-1)
        self.splits = List[FullPattern]()
        self.ignore_merges = _n(j, _at(j, 0, "model/ignore_merges")) != 0
        self.sub_prefix = String("##")
        self.max_chars = 100
        self.norm = 0
        self.maps = Dict[Int, List[Int]]()
        self.scores = List[Float64]()
        self.maxlen = 1
        self.cm = List[UInt8]()
        self.subs = List[FullPattern]()
        self.subw = List[String]()
        self.ws_split = False
        self.prepend = False
        var model = _at(j, 0, "model")
        for k in ["byte_fallback", "end_of_word_suffix", "continuing_subword_prefix"]:
            var i = _at(j, model, String(k))
            if self.kind != 1 and (_n(j, i) != 0 or _s(j, i).byte_length() > 0):
                raise Error("tokenizers: ", path, ": ", k, " is not supported")
        # vocab: {token: id} (BPE, WordPiece) or [[token, score]] (Unigram)
        var v = _at(j, model, "vocab")
        var k = v + 1
        var id = 0
        var low = 0.0
        while k < v + Int(j.n[v].size):
            var tok = _s(j, k + 1 if self.kind == 2 else k, self.kind != 2)
            id = id if self.kind == 2 else Int(j.n[k].num)
            if self.kind == 2:
                var sc = j.n[k + 2]
                self.scores.append(bitcast[DType.float64](sc.num) if sc.kind == 3 else Float64(sc.num))
                low = min(low, self.scores[id])
                self.maxlen = max(self.maxlen, tok.count_codepoints())
            self._add(id, tok.copy(), False)
            self.vocab[tok^] = id
            k += Int(j.n[k].size) if self.kind == 2 else 1
            id += 1
        # added tokens: cut out of the text before anything else
        var at = _at(j, 0, "added_tokens")
        k = at + 1
        while at >= 0 and k < at + Int(j.n[at].size):
            var content = _s(j, _at(j, k, "content"))
            self._add(_n(j, _at(j, k, "id")), content.copy(), True)
            var p = 0
            while p < len(self.specials) and self.specials[p].byte_length() >= content.byte_length():
                p += 1
            if content.byte_length() > 0:
                self.first[Int(content.as_bytes()[0])] = True
            self.specials.insert(p, content^)
            self.spid.insert(p, _n(j, _at(j, k, "id")))
            self.spf.insert(p, _n(j, _at(j, k, "lstrip")) | _n(j, _at(j, k, "rstrip")) << 1)
            k += Int(j.n[k].size)
        if self.kind == 0:
            var shift = 0  # the byte-level alphabet: printable Latin-1 as is, the rest shifted past 0xFF in order
            for b in range(256):
                var cp = b
                if b < 33 or (b > 126 and b < 161) or b == 173:
                    cp = 256 + shift
                    shift += 1
                self.inv[cp] = b
                self.bstr.append(chr(cp))
                self.bid[b] = self.vocab.get(self.bstr[b], -1)
                if self.bid[b] < 0:
                    raise Error("tokenizers: ", path, ": not a byte-level vocabulary")
            var m = _at(j, model, "merges")  # "a b" strings or [a, b] pairs, in rank order
            k = m + 1
            var rank = 0
            while m >= 0 and k < m + Int(j.n[m].size):
                var a = _s(j, k)
                var b = String()
                if j.n[k].kind == STR:
                    var sp = a.find(" ")
                    b = String(a[byte = sp + 1 :])
                    var l = String(a[byte=0:sp])
                    a = l^
                    k += 1
                else:
                    a = _s(j, k + 1)
                    b = _s(j, k + 2)
                    k += 3
                var im = self.vocab.get(a + b, -1)
                if im >= 0 and a in self.vocab and b in self.vocab:
                    self.ranks[self.vocab[a] << 32 | self.vocab[b]] = rank << 32 | im
                rank += 1
        elif self.kind == 1:
            self.unk = self.vocab.get(_s(j, _at(j, model, "unk_token")), -1)
            self.sub_prefix = _s(j, _at(j, model, "continuing_subword_prefix"))
            self.max_chars = _n(j, _at(j, model, "max_input_chars_per_word"))
            self.strip = _n(j, _at(j, 0, "decoder/cleanup")) != 0
        else:
            self.unk = _n(j, _at(j, model, "unk_id"))
            self.scores.append(low - 10.0)  # the unknown-character score, last
        self._load_pipeline(j, path)

    def _add(mut self, id: Int, var tok: String, added: Bool):
        while len(self.tokens) <= id:
            self.tokens.append(String())
            self.added.append(False)
        self.tokens[id] = tok^
        self.added[id] = self.added[id] or added

    def _load_pipeline(mut self, j: Json, path: String) raises:
        for p in _list(j, 0, "normalizer", "normalizers"):
            var ty = _s(j, _at(j, p, "type"))
            if ty == "BertNormalizer" and self.kind == 1:
                var lo = _n(j, _at(j, p, "lowercase")) != 0
                var sa = _at(j, p, "strip_accents")
                var st = lo if sa < 0 or j.n[sa].kind != 1 else _n(j, sa) != 0
                self.norm = _n(j, _at(j, p, "clean_text")) | _n(j, _at(j, p, "handle_chinese_chars")) << 1 | Int(st) << 2 | Int(lo) << 3
                self.maps = _map(STRIPLOWER if st and lo else STRIP if st else LOWER if lo else "")
            elif ty == "Precompiled" and self.kind == 2:
                self.cm = b64decode(_s(j, _at(j, p, "precompiled_charsmap")))
            elif ty == "Replace" and self.kind == 2 and _at(j, p, "pattern/Regex") >= 0:
                self.subs.append(FullPattern(_s(j, _at(j, p, "pattern/Regex"))))
                self.subw.append(_s(j, _at(j, p, "content")))
            elif not (ty == "NFC" and self.kind == 0):
                raise Error("tokenizers: ", path, ": normalizer '", ty, "' is not supported")
        for p in _list(j, 0, "pre_tokenizer", "pretokenizers"):
            var ty = _s(j, _at(j, p, "type"))
            if ty == "Split" and self.kind == 0:
                var beh = _s(j, _at(j, p, "behavior"))
                if beh != "Isolated" or _n(j, _at(j, p, "invert")) != 0:
                    raise Error("tokenizers: ", path, ": Split behavior ", beh, " is not supported")
                self.splits.append(FullPattern(_s(j, _at(j, p, "pattern/Regex"))))
            elif ty == "ByteLevel" and self.kind == 0:
                if _n(j, _at(j, p, "add_prefix_space")) != 0:
                    raise Error("tokenizers: ", path, ": add_prefix_space is not supported")
                if _n(j, _at(j, p, "use_regex")) != 0:
                    self.splits.append(FullPattern(GPT2_RE))
            elif ty == "WhitespaceSplit" and self.kind == 2:
                self.ws_split = True
            elif ty == "Metaspace" and self.kind == 2:
                var scheme = _s(j, _at(j, p, "prepend_scheme"))
                self.prepend = scheme == "always" or (scheme == "" and _n(j, _at(j, p, "add_prefix_space")) != 0)
                if scheme == "first":
                    raise Error("tokenizers: ", path, ": prepend_scheme first is not supported")
                self.strip = self.prepend
            elif not (ty == "BertPreTokenizer" and self.kind == 1):
                raise Error("tokenizers: ", path, ": pre-tokenizer '", ty, "' is not supported")

    def encode(mut self, text: String) raises -> List[Int]:
        """Ids of `text`: added tokens are cut out first, the rest is normalized, pre-tokenized and tokenized."""
        var out = List[Int]()
        var b = text.as_bytes()
        var n = len(b)
        var last = 0
        var i = 0
        var rs = False
        while i < n:
            var hit = -1
            if self.first[Int(b[i])]:
                for p in range(len(self.specials)):
                    var s = self.specials[p].as_bytes()
                    if i + len(s) <= n and Span(b)[i : i + len(s)] == s:
                        hit = p
                        break
            if hit < 0:
                i += 1
                continue
            var seg = String(unsafe_from_utf8=b[last:i])
            self._seg(_trim(seg, False) if self.spf[hit] & 1 != 0 else seg^, out, rs)
            out.append(self.spid[hit])
            rs = self.spf[hit] & 2 != 0
            i += self.specials[hit].byte_length()
            last = i
        self._seg(String(unsafe_from_utf8=b[last:n]), out, rs)
        return out^

    def _seg(mut self, var seg: String, mut out: List[Int], lstrip: Bool) raises:
        var words = List[String]()
        seg = _trim(seg, True) if lstrip else seg^
        if self.kind == 0:
            if seg.byte_length() > 0:
                words.append(seg.copy())
            for sp in self.splits:
                var next = List[String]()
                for w in words:
                    next.extend(sp.split_keep(w))
                words = next^
        elif self.kind == 1:
            words = self._words(self._bert(seg))
        else:
            words = self._meta(self._precompiled(seg))
        for w in words:
            if w in self.cache:
                out.extend(Span(self.cache[w]))
                continue
            var ids = self._bpe(w) if self.kind == 0 else self._wordpiece(w) if self.kind == 1 else self._viterbi(w)
            if len(self.cache) >= 200_000:
                self.cache.clear()
            self.cache[w.copy()] = ids.copy()
            out.extend(ids^)

    def _bpe(self, w: String) raises -> List[Int]:
        var ids = List[Int](capacity=w.byte_length())
        var whole = String()
        for x in w.as_bytes():
            ids.append(self.bid[Int(x)])
            whole += self.bstr[Int(x)] if self.ignore_merges else ""
        var direct = self.vocab.get(whole, -1) if self.ignore_merges else -1
        if direct >= 0:
            return [direct]
        if len(ids) > 1:
            self._merge(ids)
        return ids^

    def _merge(self, mut ids: List[Int]) raises:
        """Lowest rank first, leftmost on ties: a binary heap of (rank << 32 | position) over a linked list of live symbols."""
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
                    var s = i
                    for c in [2 * i + 1, 2 * i + 2]:
                        if c < len(heap) and heap[c] < heap[s]:
                            s = c
                    if s == i:
                        break
                    heap[i], heap[s] = heap[s], heap[i]
                    i = s
            var at = top & 0xFFFFFFFF
            var q = nxt[at]
            if ids[at] < 0 or q >= n:
                continue
            var r = self.ranks.get(ids[at] << 32 | ids[q], -1)
            if r < 0 or (r >> 32) != (top >> 32):  # stale entry
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

    def _bert(self, text: String) raises -> String:
        """BertNormalizer: clean_text, handle_chinese_chars, strip_accents (NFD, drop marks), lowercase, in that order."""
        var out = List[UInt8](capacity=text.byte_length())
        for c in text.codepoints():
            var cp = Int(c)
            if cp < 128 and self.norm & 1 != 0:  # ASCII fast path: no table lookups
                if cp == 9 or cp == 10 or cp == 13:
                    cp = 32
                elif cp < 32 or cp == 127:
                    continue
                out.append(UInt8(cp + 32 if self.norm & 8 != 0 and cp >= 65 and cp <= 90 else cp))
                continue
            if self.norm & 1 != 0:
                if cp == 0 or cp == 0xFFFD or (cp != 9 and cp != 10 and cp != 13 and _in(CONTROL, cp)):
                    continue
                cp = 32 if _sp(cp) else cp
            if self.norm & 2 != 0 and _in(CJK, cp):
                out.append(32)
                _put(out, cp)
                out.append(32)
            elif self.norm & 4 != 0 and _in(MARKS, cp):
                continue
            elif self.norm & 4 != 0 and cp >= 0xAC00 and cp <= 0xD7A3:  # Hangul syllable -> jamo
                var si = cp - 0xAC00
                _put(out, 0x1100 + si // 588)
                _put(out, 0x1161 + (si % 588) // 28)
                if si % 28 != 0:
                    _put(out, 0x11A7 + si % 28)
            elif cp in self.maps:
                for y in self.maps[cp]:
                    _put(out, y)
            else:
                _put(out, cp)
        return String(unsafe_from_utf8=Span(out))

    def _words(self, text: String) -> List[String]:
        """BertPreTokenizer: whitespace splits (dropped); each punctuation character is a word of its own."""
        var words = List[String]()
        var cur = List[UInt8]()
        for c in text.codepoints():
            var cp = Int(c)
            var punct = _pu(cp)
            if punct or _sp(cp):
                if len(cur) > 0:
                    words.append(String(unsafe_from_utf8=Span(cur)))
                    cur.clear()
                if punct:
                    words.append(String(c))
            else:
                _put(cur, cp)
        if len(cur) > 0:
            words.append(String(unsafe_from_utf8=Span(cur)))
        return words^

    def _wordpiece(self, word: String) raises -> List[Int]:
        """Greedy longest match from the left; a word with any unmatched part is one [UNK]."""
        var pos = List[Int]()  # byte offset of every character, then the end
        var run = 0
        for p in word.codepoint_slices():
            pos.append(run)
            run += p.byte_length()
        pos.append(run)
        var n = len(pos) - 1
        var b = word.as_bytes()
        var ids = List[Int]()
        var at = 0
        while n <= self.max_chars and at < n:
            var end = n
            var hit = -1
            while at < end and hit < 0:
                var sub = String(unsafe_from_utf8=b[pos[at] : pos[end]])
                hit = self.vocab.get(self.sub_prefix + sub if at > 0 else sub, -1)
                end -= Int(hit < 0)
            if hit < 0:
                break
            ids.append(hit)
            at = end
        return ids^ if at >= n and n <= self.max_chars else [self.unk]

    def _precompiled(self, text: String) raises -> String:
        """Sentencepiece's normalizer, as the crate runs it: a grapheme under 6 bytes is looked up whole (shortest match), else
        every code point on its own (longest match); then the Replace normalizers."""
        if len(self.cm) == 0:
            return text.copy()
        var out = List[UInt8]()
        for g in text.graphemes():
            var r = self._prefixes(g.as_bytes()) if g.byte_length() < 6 else List[Int]()
            if len(r) > 0:
                self._emit(out, r[0])
                continue
            for c in g.codepoint_slices():
                r = self._prefixes(c.as_bytes())
                if len(r) > 0:
                    self._emit(out, r[len(r) - 1])
                else:
                    out.extend(c.as_bytes())
        var s = String(unsafe_from_utf8=Span(out))
        for i in range(len(self.subs)):
            var res = List[UInt8]()
            var last = 0
            for m in self.subs[i].findall_spans(s):
                res.extend(s.as_bytes()[last : m.start])
                res.extend(self.subw[i].as_bytes())
                last = m.end
            res.extend(s.as_bytes()[last:])
            s = String(unsafe_from_utf8=Span(res))
        return s^

    def _u32(self, i: Int) -> Int:
        return Int(self.cm[4 * i + 4]) | Int(self.cm[4 * i + 5]) << 8 | Int(self.cm[4 * i + 6]) << 16 | Int(self.cm[4 * i + 7]) << 24

    def _prefixes(self, key: Span[UInt8, _]) -> List[Int]:
        """Pool offsets of the replacements of every prefix of `key` in the double-array trie, shortest first."""
        var out = List[Int]()
        var unit = self._u32(0)
        var pos = (unit >> 10) << ((unit & 0x200) >> 6)
        for c in key:
            pos ^= Int(c)
            unit = self._u32(pos)
            if (unit & 0x800000FF) != Int(c):
                break
            pos ^= (unit >> 10) << ((unit & 0x200) >> 6)
            if (unit >> 8) & 1 != 0:
                out.append(self._u32(pos) & 0x7FFFFFFF)
        return out^

    def _emit(self, mut out: List[UInt8], off: Int):
        var i = 8 + (Int(self.cm[0]) | Int(self.cm[1]) << 8 | Int(self.cm[2]) << 16 | Int(self.cm[3]) << 24) + off - 4
        while self.cm[i] != 0:
            out.append(self.cm[i])
            i += 1

    def _meta(self, text: String) -> List[String]:
        """WhitespaceSplit, then Metaspace: spaces become U+2581, one is prepended, and each U+2581 starts a piece."""
        var words = List[String]()
        var cur = List[UInt8]()
        for c in text.codepoints():
            if _sp(Int(c)) and self.ws_split:
                if len(cur) > 0:
                    words.append(String(unsafe_from_utf8=Span(cur)))
                    cur.clear()
            else:
                _put(cur, Int(c))
        if len(cur) > 0:
            words.append(String(unsafe_from_utf8=Span(cur)))
        var out = List[String]()
        for w in words:
            var s = w.replace(" ", SP)
            s = SP + s if self.prepend and not s.startswith(SP) else s^
            var piece = String()
            for c in s.codepoint_slices():
                if c == SP and piece.byte_length() > 0:
                    out.append(piece^)
                    piece = String()
                piece += c
            if piece.byte_length() > 0:
                out.append(piece^)
        return out^

    def _viterbi(self, w: String) raises -> List[Int]:
        """Best segmentation by score; ties go to the earliest start, a character outside the vocabulary costs the lowest score - 10."""
        var pos = List[Int]()
        var run = 0
        for p in w.codepoint_slices():
            pos.append(run)
            run += p.byte_length()
        pos.append(run)
        var n = len(pos) - 1
        var b = w.as_bytes()
        var best = List[Float64](length=n + 1, fill=-1e300)
        var prev = List[Int](length=n + 1, fill=0)
        var tid = List[Int](length=n + 1, fill=0)
        best[0] = 0.0
        for e in range(1, n + 1):
            for s in range(max(0, e - self.maxlen), e):
                var id = self.vocab.get(String(unsafe_from_utf8=b[pos[s] : pos[e]]), -1)
                if id < 0 and e - s > 1:
                    continue
                var sc = self.scores[id] if id >= 0 else self.scores[len(self.scores) - 1]
                if best[s] + sc > best[e]:
                    best[e] = best[s] + sc
                    prev[e] = s
                    tid[e] = id if id >= 0 else self.unk
        var ids = List[Int]()
        var e = n
        while e > 0:
            if tid[e] != self.unk or len(ids) == 0 or ids[len(ids) - 1] != self.unk:  # consecutive unknowns fuse into one
                ids.append(tid[e])
            e = prev[e]
        ids.reverse()
        return ids^

    def decode(self, ids: List[Int]) raises -> String:
        """The text of `ids`, added tokens included. Byte-level: invalid UTF-8 becomes U+FFFD."""
        var out = List[UInt8]()
        for id in ids:
            if id < 0 or id >= len(self.tokens):
                raise Error("tokenizers: id ", id, " is out of range")
            var t = self.tokens[id].copy()
            if self.kind == 1:
                var sub = t.startswith(self.sub_prefix) and not self.added[id]
                t = String(t[byte = self.sub_prefix.byte_length() :]) if sub else (" " + t if len(out) > 0 else t^)
            elif self.kind == 2:
                t = t.replace(SP, " ")
                t = String(t[byte=1:]) if len(out) == 0 and self.strip and t.startswith(" ") else t^
            else:
                var bytes = List[UInt8]()
                var raw = self.added[id]
                for c in t.codepoints():
                    if Int(c) < len(self.inv) and self.inv[Int(c)] >= 0:
                        bytes.append(UInt8(self.inv[Int(c)]))
                    else:
                        raw = True
                if not raw:
                    out.extend(bytes^)
                    continue
            out.extend(t.as_bytes())
        var s = String(from_utf8_lossy=Span(out))
        if self.kind == 1 and self.strip:
            for r in [" .=.", " ?=?", " !=!", " ,=,", " n't=n't", " 'm='m", " 's='s", " 've='ve", " 're='re"]:
                var kv = r.split("=")
                s = s.replace(String(kv[0]), String(kv[1]))
        return s^
