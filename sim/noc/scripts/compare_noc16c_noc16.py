#!/usr/bin/env python3
import csv
from pathlib import Path
root=Path(__file__).resolve().parents[1]/"results"
def load(path):
    with path.open(newline="") as stream:
        return {(r["rate"],r["policy"]):r for r in csv.DictReader(stream)}
base=load(root/"noc16_grant_comparison"/"by_rate.csv")
conc=load(root/"noc16c_grant_comparison"/"by_rate.csv")
fields=["rate","noc16_delivered","noc16c_delivered","delivered_change_percent",
        "noc16_network_latency","noc16c_network_latency","latency_change_percent",
        "noc16_packet_latency","noc16c_packet_latency",
        "noc16_llch_jain","noc16c_llch_jain"]
rows=[]
for key in sorted(set(base)&set(conc),key=lambda k:float(k[0])):
    if key[1]!="weighted": continue
    a,b=base[key],conc[key]
    at,bt=float(a["mean_delivered"]),float(b["mean_delivered"])
    al,bl=float(a["mean_network_latency"]),float(b["mean_network_latency"])
    rows.append(dict(rate=key[0],noc16_delivered=f"{at:.9f}",noc16c_delivered=f"{bt:.9f}",
      delivered_change_percent=f"{100*(bt/at-1):.6f}",
      noc16_network_latency=f"{al:.9f}",noc16c_network_latency=f"{bl:.9f}",
      latency_change_percent=f"{100*(bl/al-1):.6f}",
      noc16_packet_latency=a["mean_packet_latency"],noc16c_packet_latency=b["mean_packet_latency"],
      noc16_llch_jain=a["mean_llch_jain"],noc16c_llch_jain=b["mean_llch_jain"]))
out=root/"noc16c_vs_noc16_weighted_by_rate.csv"
with out.open("w",newline="") as stream:
    writer=csv.DictWriter(stream,fieldnames=fields);writer.writeheader();writer.writerows(rows)
print(out)
