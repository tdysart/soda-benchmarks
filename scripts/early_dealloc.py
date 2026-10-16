#!/usr/bin/env python3
"""Move each memref.dealloc to just after the last use of the buffer (or of any view of it)."""
import re, sys
src = open(sys.argv[1]).read().split('\n')
# statements of the (single) function body: lines indented exactly 4 spaces start a statement,
# deeper lines and lines closing a region belong to the statement before.
start = next(i for i, l in enumerate(src) if l.startswith('  func.func'))
end = next(i for i in range(len(src) - 1, -1, -1) if src[i].startswith('  }'))
body = src[start + 1:end]
stmts = []
for l in body:
    if re.match(r'^    \S', l) and not l.strip().startswith(('}', '^')):
        stmts.append([l])
    else:
        stmts[-1].append(l)
VIEW = re.compile(r'(%\w+) = memref\.(subview|collapse_shape|expand_shape|cast|reinterpret_cast|transpose|view) (%\w+)')
ALLOC = re.compile(r'(%\w+) = memref\.alloc\b')
DEALLOC = re.compile(r'^\s+memref\.dealloc (%\w+)')
group = {}                      # value -> alloc it belongs to
for st in stmts:
    t = st[0]
    m = ALLOC.search(t)
    if m: group[m.group(1)] = m.group(1)
    m = VIEW.search(t)
    if m and m.group(3) in group: group[m.group(1)] = group[m.group(3)]
last = {}
for i, st in enumerate(stmts):
    if DEALLOC.match(st[0]): continue
    text = '\n'.join(st)
    for v, a in group.items():
        if re.search(re.escape(v) + r'(?![\w])', text): last[a] = i
deallocs = {DEALLOC.match(st[0]).group(1): st for st in stmts if DEALLOC.match(st[0])}
out = []
for i, st in enumerate(stmts):
    if DEALLOC.match(st[0]): continue
    out.append(st)
    for a in [a for a, j in last.items() if j == i and a in deallocs]:
        out.append(deallocs[a])
# deallocs of buffers that are never used keep their place at the end
for a, st in deallocs.items():
    if a not in last: out.append(st)
open(sys.argv[2], 'w').write('\n'.join(src[:start + 1] + [l for st in out for l in st] + src[end:]))
