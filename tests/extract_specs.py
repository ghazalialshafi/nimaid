#!/usr/bin/env python3
"""Extract (input chart, expectations) from mermaid's flowchart parser specs into JSON."""
import re, json, sys, glob, os
SPEC_DIR = sys.argv[1]
OUT = sys.argv[2]

def unescape_js(s, q):
    out=[];i=0
    while i<len(s):
        c=s[i]
        if c=='\\' and i+1<len(s):
            n=s[i+1]; i+=2
            out.append({'n':'\n','t':'\t','r':'\r','\\':'\\',"'":"'",'"':'"','`':'`','$':'$'}.get(n,'\\'+n))
        else: out.append(c); i+=1
    return ''.join(out)

LIT = re.compile(r"""'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`((?:[^`\\]|\\.)*)`""", re.S)

def parse_arg(text, start):
    """Parse concatenation of string literals starting at start; return (string, end) or None."""
    pos=start; parts=[]
    while True:
        while pos<len(text) and text[pos] in ' \t\r\n': pos+=1
        m=LIT.match(text,pos)
        if not m: return None
        if m.group(1) is not None: parts.append(unescape_js(m.group(1),"'"))
        elif m.group(2) is not None: parts.append(unescape_js(m.group(2),'"'))
        else:
            if '${' in m.group(3): return None
            parts.append(unescape_js(m.group(3),'`'))
        pos=m.end()
        while pos<len(text) and text[pos] in ' \t\r\n': pos+=1
        if pos<len(text) and text[pos]=='+': pos+=1; continue
        return ''.join(parts), pos

def block_end(text, i):
    depth=0; n=len(text); instr=None
    while i<n:
        c=text[i]
        if instr:
            if c=='\\': i+=2; continue
            if c==instr: instr=None
        elif c in '\'"`': instr=c
        elif c=='/' and text[i:i+2]=='//':
            while i<n and text[i]!='\n': i+=1
            continue
        elif c=='{': depth+=1
        elif c=='}':
            depth-=1
            if depth==0: return i
        i+=1
    return n

def js_value(s):
    s=s.strip()
    if s in ('true','false'): return s=='true'
    if s=='undefined': return None
    if re.fullmatch(r'-?\d+(\.\d+)?',s): return float(s) if '.' in s else int(s)
    r=parse_arg(s,0)
    if r and r[1]==len(s.rstrip()): return r[0]
    if s.startswith('['):
        try:
            return json.loads(re.sub(r"'((?:[^'\\]|\\.)*)'", lambda m: json.dumps(m.group(1)), s))
        except Exception: pass
    raise ValueError(s)

EXPECT = re.compile(r"expect\(\s*(.+?)\s*\)\s*\.(toBe|toEqual|toContain|toHaveLength)\(\s*(.+?)\s*\)\s*;", re.S)
cases=[]
for f in sorted(sorted(glob.glob(os.path.join(SPEC_DIR,'*.spec.js'))+glob.glob(os.path.join(SPEC_DIR,'*.spec.ts')))):
    text=open(f).read()
    for m in re.finditer(r"\bit\(\s*(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"|`([^`]*)`)\s*,", text):
        name=next(g for g in m.groups() if g is not None)
        bstart=text.index('{',m.end()); bend=block_end(text,bstart)
        body=text[bstart:bend]
        inputs=[]
        for pm in re.finditer(r"parser\.parse\(",body):
            r=parse_arg(body,pm.end())
            inputs.append(r[0] if r else None)
        if not inputs or inputs[0] is None or len(inputs)>1 and any(i is None for i in inputs):
            cases.append({'file':os.path.basename(f),'name':name,'skip':'dynamic input'}); continue
        # only the last parse call's state is observable unless db is not cleared; use last
        chart=inputs[-1]
        exps=[]; unparsed=0
        for em in EXPECT.finditer(body):
            lhs,op,rhs=em.group(1),em.group(2),em.group(3)
            try: val=js_value(rhs)
            except Exception: unparsed+=1; continue
            exps.append({'lhs':re.sub(r'\s+','',lhs),'op':op,'rhs':val})
        aliases={a:int(i) for a,i in re.findall(r"(?:const|let)\s+(\w+)\s*=\s*subgraphs\[(\d+)\]",body)}
        for a,i in re.findall(r"(?:const|let)\s+(\w+)\s*=\s*subgraphs\.find\(.*?id\s*===?\s*'(\w+)'",body): aliases[a]=i
        cases.append({'file':os.path.basename(f),'name':name,'aliases':aliases,'chart':chart,'expect':exps,'unparsed':unparsed,
                      'multi':len(inputs)>1})
json.dump(cases,open(OUT,'w'),indent=1)
runnable=[c for c in cases if 'chart' in c]
print(len(cases),'cases;',len(runnable),'runnable;',sum(len(c['expect']) for c in runnable),'assertions')
