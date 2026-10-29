import json,sys
d=json.load(open(sys.argv[1])); mode=sys.argv[2]; frm=sys.argv[3]; count=int(sys.argv[4])
S=d["series"]; items=d["items"]
start=next(i for i,it in enumerate(items) if f"{S[it[1]][0]} ({S[it[1]][1]})"==frm)
blocks=[]
for it in items[start:]:
    cv,si,num,kind=it
    if mode=="esencial" and kind==0: continue
    tag="" if kind>0 else " (extra)"
    if blocks and blocks[-1][0]==si and blocks[-1][3]==tag: blocks[-1][2]=num; blocks[-1][4]+=1
    else: blocks.append([si,num,num,tag,1])
    if len(blocks)>count: break
for b in blocks[:count]:
    s=S[b[0]]; print(f"- {s[0]} ({s[1]}) #{b[1]}"+(f"–{b[2]}" if b[1]!=b[2] else "")+b[3])
