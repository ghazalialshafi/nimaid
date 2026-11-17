import json, random, subprocess, sys, os
seed0=int(sys.argv[1]) if len(sys.argv)>1 else 0
N=int(sys.argv[2]) if len(sys.argv)>2 else 200
here=os.path.dirname(os.path.abspath(__file__))
ref=os.path.join(here,"../../ref/ref.js")
def gen(seed):
    r=random.Random(seed)
    n=r.randint(1,r.choice([6,12,25,80]))
    g={"rankdir":r.choice(["TB","BT","LR","RL"]),"nodesep":r.choice([50,20]),"ranksep":r.choice([50,30]),"edgesep":20,
       "marginx":r.choice([0,10]),"marginy":r.choice([0,10]),"acyclicer":r.choice(["","greedy"]),
       "ranker":r.choice(["","","tight-tree","longest-path"]),"align":r.choice(["","UL","DR"]),"rankalign":r.choice(["center","top","bottom"])}
    g={k:v for k,v in g.items() if v!=""}
    nodes=[{"id":f"n{i}","width":r.randint(10,80),"height":r.randint(10,50)} for i in range(n)]
    if r.random()<0.4 and n>3:
        k=r.randint(1,3)
        for c in range(k): nodes.append({"id":f"c{c}","width":0,"height":0})
        for i in range(n):
            if r.random()<0.6:
                nodes[i]["parent"]=f"c{r.randrange(k)}"
        if k>1 and r.random()<0.5: nodes[n+1]["parent"]="c0"
    edges=[]
    for _ in range(r.randint(0,int(n*1.6))):
        e={"v":f"n{r.randrange(n)}","w":f"n{r.randrange(n)}"}
        if e["v"]==e["w"] and r.random()<0.7: continue
        if r.random()<0.3: e.update(width=r.randint(5,40),height=r.randint(5,20),labelpos=r.choice(["l","r","c"]))
        if r.random()<0.2: e["minlen"]=r.randint(1,3)
        if r.random()<0.2: e["weight"]=r.randint(1,4)
        if r.random()<0.1: e["name"]=f"m{r.randrange(2)}"
        edges.append(e)
    spec={"graph":g,"nodes":nodes,"edges":edges}
    if r.random()<0.35:
        for nd in nodes:
            if nd["id"].startswith("c") and r.random()<0.7: nd["rankdir"]=r.choice(["TB","LR","BT","RL"])
    if r.random()<0.25: spec["corePath"]=r.sample([f"n{i}" for i in range(n)],min(n,r.randint(1,4)))
    if r.random()<0.1: spec["customOrder"]=True
    if r.random()<0.4:
        spec["second"]=[{"v":f"n{r.randrange(n)}","w":f"n{r.randrange(n)}"} for _ in range(r.randint(1,3))]
        if r.random()<0.15: spec["useDynamic"]=False
    return spec
def close(a,b):
    if isinstance(a,dict): return a.keys()==b.keys() and all(close(a[k],b[k]) for k in a)
    if isinstance(a,list): return len(a)==len(b) and all(close(x,y) for x,y in zip(a,b))
    if isinstance(a,(int,float)) and isinstance(b,(int,float)): return abs(a-b)<1e-6
    return a==b
bad=0
for s in range(seed0,seed0+N):
    spec=gen(s); p=f"/tmp/f{s}.json"; json.dump(spec,open(p,"w"))
    a=subprocess.run(["node",ref,p],capture_output=True,text=True)
    b=subprocess.run([os.path.join(here,"driver"),p],capture_output=True,text=True,timeout=60)
    if a.returncode!=0:
        os.remove(p); continue   # reference itself rejects this input
    if b.returncode!=0: print("seed",s,"NIM CRASH",b.stderr.strip()[-150:]); bad+=1; continue
    ja,jb=json.loads(a.stdout),json.loads(b.stdout)
    for nd in ja['nodes'].values(): nd.setdefault('x',0.0); nd.setdefault('y',0.0)
    if not close(ja,jb): print("seed",s,"MISMATCH"); bad+=1
    else: os.remove(p)
print("done, failures:",bad,"of",N)
