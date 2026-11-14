import sys, re, json, os
src = open(sys.argv[1], encoding='utf-8', errors='replace').read()
TOK = re.compile(r'''\s+|--[^\n]*|"((?:\\.|[^"\\])*)"|(-?\d+\.?\d*(?:[eE][-+]?\d+)?)|(true|false|nil)(?!\w)|([\[\]{}=,])|([A-Za-z_]\w*)''')
ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v'}


def unescape(m):
    g = m.group(1)
    return chr(int(g)) if g.isdigit() else ESCAPES.get(g, g)


toks = []
pos = 0
while pos < len(src):
    m = TOK.match(src, pos)
    if not m:
        raise SystemExit(f"tokenize error at {pos}: {src[pos:pos+40]!r}")
    pos = m.end()
    if m.group(0).isspace() or m.group(0).startswith('--'):
        continue
    if m.group(1) is not None or m.group(0) == '""':
        s = m.group(1) if m.group(1) is not None else ""
        # One pass, so an escaped backslash followed by a letter is not read as an escape (e.g. "a\\\\new").
        s = re.sub(r'\\(\d{1,3}|.)', unescape, s, flags=re.S)
        toks.append(('s', s))
    elif m.group(2) is not None:
        n = m.group(2); toks.append(('n', float(n) if ('.' in n or 'e' in n.lower()) else int(n)))
    elif m.group(3) is not None:
        toks.append(('k', {'true': True, 'false': False, 'nil': None}[m.group(3)]))
    elif m.group(4) is not None:
        toks.append(('p', m.group(4)))
    else:
        toks.append(('i', m.group(5)))
p = 0
def peek(): return toks[p] if p < len(toks) else (None, None)
def parse_value():
    global p
    t, v = toks[p]
    if (t, v) == ('p', '{'):
        p += 1
        d = {}; idx = 1
        while True:
            t, v = toks[p]
            if (t, v) == ('p', '}'):
                p += 1; return d
            if (t, v) == ('p', '['):
                p += 1; k = toks[p][1]; p += 2  # key, ']'
                assert toks[p] == ('p', '='); p += 1
                d[k] = parse_value()
            elif t == 'i' and toks[p+1] == ('p', '='):
                k = v; p += 2; d[k] = parse_value()
            else:
                d[idx] = parse_value(); idx += 1
            if peek() == ('p', ','): p += 1
    p += 1
    return v
if len(toks) < 3 or toks[0][0] != 'i' or toks[1] != ('p', '='):
    raise SystemExit('expected a SavedVariables file: Name = { ... }')
p = 2
DB = parse_value()
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), 'parsed.json')
json.dump(DB, open(out, 'w'), default=str)
print('wrote', out)
print("top-level keys:", {k: (len(v) if isinstance(v, (dict, list)) else v) for k, v in DB.items()})
