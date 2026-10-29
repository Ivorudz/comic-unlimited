import re,html,os,glob,json,sys
from collections import Counter
def norm(s):
    s=html.unescape(s).lower(); s=re.sub(r'^the ','',s)
    return re.sub(r'[^a-z0-9]','',s.replace('&','and'))
def title(p):
    t=os.path.basename(p)[:-4]
    t=re.sub(r'^\[[^\]]*\]\s*','',t); t=re.sub(r'^\[[^\]]*\]\s*','',t)
    t=re.sub(r'\s*\([^)]*\)','',t); t=re.sub(r'^\d{4}(-\d{4})?\s*-\s*','',t)
    return t.strip()
core={}   # (normname, volume) -> event title
for p in glob.glob(sys.argv[1]+'/Marvel/Events/**/*.cbl',recursive=True)+glob.glob(sys.argv[1]+'/DC/Events/**/*.cbl',recursive=True):
    t=title(p); nt=norm(t)
    if len(nt)<3: continue
    d=open(p,encoding='utf-8',errors='replace').read()
    books=re.findall(r'<Book Series="([^"]*)" Number="[^"]*" Volume="([^"]*)"',d)
    c=Counter((norm(s),v) for s,v in books)
    for (ns,v),n in c.items():
        # la serie del evento: mismo nombre que el evento (o el evento empieza con ella, ej "Civil War" en "Civil War (2006)")
        if ns==nt:
            core[(ns,v)]=t
json.dump({f"{k[0]}|{k[1]}":v for k,v in core.items()},open(sys.argv[2],'w'),indent=0)
print(len(core),'series núcleo de eventos')
