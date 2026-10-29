import sys,re,html,json,os
from collections import Counter
def norm(s):
    s=html.unescape(s).lower(); s=re.sub(r'^the ','',s)
    return re.sub(r'[^a-z0-9]','',s.replace('&','and'))
root, corefile, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
core=json.load(open(corefile))
MARVEL=[(1961,"Edad de Plata"),(1970,"Edad de Bronce"),(1984,"Empieza la Era Moderna"),(1997,"Los héroes vuelven"),
        (2004,"Marvel Disassembled"),(2012,"Marvel NOW!"),(2015,"All-New, All-Different"),(2018,"Fresh Start"),(2021,"Timeless"),(2024,"Hoy")]
DC=[(1938,"Edad de Oro"),(1956,"Edad de Plata"),(1970,"Edad de Bronce"),(1986,"Después de Crisis"),(2011,"Los Nuevos 52"),
    (2016,"Renacimiento"),(2021,"Infinite Frontier"),(2023,"Dawn of DC"),(2024,"DC All In")]
KEYWORDS={"avengers":["avengers"],"xmen":["xmen","xfactor","newmutants"],"spiderman":["spiderman"],"batman":["batman","detectivecomics"],"justiceleague":["justiceleague","jla"]}
# Camino "Esencial": solo las series principales de cada ruta (nombre exacto, cualquier volumen), sus anuales y
# Giant-Size, más el centro de cada evento. El resto de las series propias de CBRO pasa a ser extra.
PRINCIPAL={
 "avengers":["avengers","newavengers","mightyavengers","uncannyavengers","darkavengers","secretavengers",
             "westcoastavengers","avengerswestcoast","avengersforever"],
 "xmen":["xmen","uncannyxmen","allnewxmen","astonishingxmen","newxmen","xmenblue","xmengold","xmenred",
         "wolverineandthexmen","extraordinaryxmen","immortalxmen"],
 "spiderman":["amazingspiderman","spectacularspiderman","peterparkerspectacularspiderman","superiorspiderman",
              "webofspiderman","spiderman","sensationalspiderman","peterparkerspiderman","friendlyneighborhoodspiderman"],
 "batman":["batman","detectivecomics","batmanandrobin","batmanincorporated"],
 "justiceleague":["justiceleague","justiceleagueofamerica","jla","justiceleagueinternational","justiceleagueamerica"],
}
def principal(rid,name):
    n=norm(name)
    return any(n in (p,p+"annual","giantsize"+p) for p in PRINCIPAL[rid])
ROUTES=[
 ("avengers","Avengers",MARVEL,"Marvel/Teams/Avengers/[Marvel] Avengers with events (WEB-CBRO).cbl","Marvel/Teams/Avengers/[Marvel] Avengers no events (WEB-CBRO).cbl",["avengers","newavengers","mightyavengers","uncannyavengers"]),
 ("xmen","X-Men",MARVEL,"Marvel/Teams/X-Men/WEB-CBRO/[Marvel] X-Men with events (WEB-CBRO).cbl","Marvel/Teams/X-Men/WEB-CBRO/[Marvel] X-Men no events (WEB-CBRO).cbl",["xmen","uncannyxmen","allnewxmen","astonishingxmen","newxmen","xmenblue","xmengold","xmenred"]),
 ("spiderman","Spider-Man",MARVEL,"Marvel/Characters/Spider-Man/CBRO/[Marvel] Spider-Man with events (WEB-CBRO).cbl","Marvel/Characters/Spider-Man/CBRO/[Marvel] Spider-Man no events (WEB-CBRO).cbl",["amazingspiderman","spectacularspiderman","peterparkerspectacularspiderman","superiorspiderman","ultimatespiderman","webofspiderman"]),
 ("batman","Batman",DC,"DC/Characters/Batman/[DC Comics] Batman with events (WEB-CBRO).cbl","DC/Characters/Batman/[DC Comics] Batman no events (WEB-CBRO).cbl",["batman","detectivecomics","batmanandrobin"]),
 ("justiceleague","Liga de la Justicia",DC,"DC/Teams/Justice League/[DC Comics] Justice League with events (WEB-CBRO).cbl","DC/Teams/Justice League/[DC Comics] Justice League no events (WEB-CBRO).cbl",["justiceleague","justiceleagueofamerica","jla","justiceleagueinternational"]),
]
def load(f):
    d=open(os.path.join(root,f),encoding='utf-8',errors='replace').read()
    out=[]
    for m in re.finditer(r'<Book ([^>]*)>\s*<Database Name="cv" Series="(\d*)" Issue="(\d*)"',d):
        a=dict(re.findall(r'(\w+)="([^"]*)"',m.group(1)))
        out.append((html.unescape(a.get("Series","")),a.get("Number",""),a.get("Volume",""),int(a.get("Year") or 0),int(m.group(3))))
    return out
def num1(n):
    try: return float(n)<=1
    except: return False
report=[]
for rid,rtitle,eras,wf,nf,flag in ROUTES:
    W=load(wf); N=load(nf)
    # Series propias de la ruta: las que aparecen en la lista "sin eventos" (todos sus números son esenciales).
    own={(b[0],b[2]) for b in N}
    # También las series con el nombre de la ruta (por ejemplo The Mighty Avengers o Dark Avengers, que CBRO
    # saca enteras de "sin eventos" porque todos sus números cruzan con algún evento).
    own|={(b[0],b[2]) for b in W if any(k in norm(b[0]) for k in KEYWORDS[rid])}
    series=[]; sidx={}; items=[]
    for name,num,vol,year,cvi in W:
        key=(name,vol)
        if key not in sidx: sidx[key]=len(series); series.append([name,int(vol) if vol.isdigit() else 0])
        kind=1 if (name,vol) in own else (2 if f"{norm(name)}|{vol}" in core else 0)
        items.append([cvi,sidx[key],num,kind,year])
    counts=Counter(it[1] for it in items if it[3]==1)
    # Títulos principales de la ruta (nombre exacto), con 12 números o más en la lista.
    isflag=lambda it: it[3]==1 and counts[it[1]]>=12 and norm(series[it[1]][0]) in flag
    def era_of(y):
        idx=0
        for k,(start,_) in enumerate(eras):
            if y>=start: idx=k
        return idx
    # Era de cada posición: según el último número de la serie principal (las miniseries "retro" no la cambian).
    # Año de cada posición = el menor año de los títulos principales que vienen después
    # (así una miniserie "retro" ubicada en los 60 no adelanta la era).
    suffix=[0]*len(items); low=None
    for i in range(len(items)-1,-1,-1):
        it=items[i]
        if isflag(it) and it[4]: low=it[4] if low is None else min(low,it[4])
        suffix[i]=low if low is not None else 0
    stages=[]; cur=-1
    for i,it in enumerate(items):
        y=suffix[i] or it[4]
        e=era_of(y) if y else max(cur,0)
        if e>cur:
            start,name=eras[e]; end=eras[e+1][0] if e+1<len(eras) else None
            stages.append({"t":name,"y":f"{start}–{end}" if end else f"{start}–","i":i}); cur=e
    # Puntos de partida (cada #1 de una serie principal) y eventos.
    marks=[]; seen=set()
    for i,it in enumerate(items):
        key=it[1]
        if key in seen: continue
        if it[3]==2: seen.add(key); marks.append({"i":i,"t":f"{series[key][0]} ({series[key][1]})","k":"e"})
        elif isflag(it) and num1(it[2]): seen.add(key); marks.append({"i":i,"t":f"{series[key][0]} ({series[key][1]})","k":"s"})
    # Las series propias que no son principales pasan a ser extras (lo esencial queda corto y claro).
    for it in items:
        if it[3]==1 and not principal(rid,series[it[1]][0]): it[3]=0
    data={"id":rid,"title":rtitle,"source":"Comic Book Reading Orders (CBRO), vía CBL-ReadingLists",
          "series":series,"items":[it[:4] for it in items],"stages":stages,"marks":marks}
    json.dump(data,open(os.path.join(outdir,f"ruta-{rid}.json"),"w"),separators=(",",":"),ensure_ascii=False)
    report.append((rtitle,items,stages,marks,series))
for rtitle,items,stages,marks,series in report:
    ess=sum(1 for it in items if it[3]>0)
    print(f"\n### {rtitle}: {len(items)} con todo · {ess} esenciales · {len(stages)} eras")
    for j,s in enumerate(stages):
        end=stages[j+1]["i"] if j+1<len(stages) else len(items)
        part=items[s["i"]:end]
        print(f"  ERA {s['t']} ({s['y']}): {sum(1 for it in part if it[3]>0)} esenciales / {len(part)} con todo")
        for m in marks:
            if s["i"]<=m["i"]<end: print(f"      {'★ Empezá por acá:' if m['k']=='s' else '⚡ Evento:'} {m['t']}")
