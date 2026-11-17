import re, sys, difflib
def funcs(path):
    lines = open(path).read().split('\n')
    out, i = {}, 0
    while i < len(lines):
        m = re.match(r'^(?:static\s+)?(?:const\s+)?[\w\s\*]+?\b(\w+)\s*\(', lines[i])
        if m and not lines[i].startswith((' ', '\t', '#', '/', '*')) and not lines[i].rstrip().endswith(';'):
            name, start = m.group(1), i
            while i < len(lines) and lines[i] != '}':
                i += 1
            body = [l for l in lines[start:i+1]]
            out[name] = body
        i += 1
    return out
a, b = funcs(sys.argv[1]), funcs(sys.argv[2])
norm = lambda body: [re.sub(r'\s+', ' ', l).strip() for l in body if l.strip()]
same, changed = [], []
for n in sorted(set(a) & set(b)):
    (same if norm(a[n]) == norm(b[n]) else changed).append(n)
print("IDENTICAL:", len(same))
print("ONLY IN 7.0:", sorted(set(a) - set(b)))
print("ONLY IN MAINLINE:", sorted(set(b) - set(a)))
print("CHANGED:", changed)
if len(sys.argv) > 3:
    for n in changed:
        print("\n=====", n)
        for l in difflib.unified_diff(norm(a[n]), norm(b[n]), lineterm='', n=1):
            if not l.startswith(('---', '+++')):
                print(l)
