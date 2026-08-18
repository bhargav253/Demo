#!/usr/bin/env python3
import csv
from pathlib import Path

root=Path(__file__).resolve().parents[1]/"results"
def load(path):
    with path.open(newline="") as stream:
        return {(r["rate"],r["policy"]):r for r in csv.DictReader(stream)}
n16=load(root/"noc16_grant_comparison"/"by_rate.csv")
n12=load(root/"noc12_grant_comparison"/"by_rate.csv")
fields=["rate","policy","noc16_delivered","noc12_delivered","delivered_change_percent",
        "noc16_network_latency","noc12_network_latency","latency_change_percent",
        "noc16_llch_jain","noc12_llch_jain"]
rows=[]
for key in sorted(set(n16)&set(n12),key=lambda k:(float(k[0]),k[1])):
    a,b=n16[key],n12[key]
    at,bt=float(a["mean_delivered"]),float(b["mean_delivered"])
    al,bl=float(a["mean_network_latency"]),float(b["mean_network_latency"])
    rows.append(dict(rate=key[0],policy=key[1],noc16_delivered=f"{at:.9f}",
      noc12_delivered=f"{bt:.9f}",delivered_change_percent=f"{100*(bt/at-1):.6f}",
      noc16_network_latency=f"{al:.9f}",noc12_network_latency=f"{bl:.9f}",
      latency_change_percent=f"{100*(bl/al-1):.6f}",
      noc16_llch_jain=a["mean_llch_jain"],noc12_llch_jain=b["mean_llch_jain"]))
out=root/"noc12_vs_noc16_by_rate.csv"
with out.open("w",newline="") as stream:
    writer=csv.DictWriter(stream,fieldnames=fields);writer.writeheader();writer.writerows(rows)
print(out)
