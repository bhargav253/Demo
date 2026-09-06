#!/usr/bin/env python3
"""Compare matched NoC16 RR and weighted-grant phase-3 runs."""

import csv
import math
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


def load_runs(directory):
    with (directory / "runs.csv").open(newline="") as stream:
        return {(row["rate"], row["seed"]): row for row in csv.DictReader(stream)}


def llch_fairness(directory, rate, seed, llch_count):
    candidates = []
    for path in directory.glob("r*_s{}.log".format(seed)):
        encoded = path.stem.split("_s", 1)[0][1:].replace("p", ".")
        if abs(float(encoded) - float(rate)) < 1.0e-12:
            candidates.append(path)
    if len(candidates) != 1:
        raise RuntimeError("expected one log for rate={} seed={}, found {}".format(
            rate, seed, candidates))
    log_path = candidates[0]
    tag = log_path.stem
    log = log_path.read_text(errors="replace")
    match = re.search(r"Warmed up \.\.\.Time used is (\d+)", log)
    begin = int(match.group(1)) if match else 300
    measurement_cycles = int(os.environ.get("NOC16_MEASUREMENT_CYCLES", "900"))
    measurement_end = begin + measurement_cycles
    values = defaultdict(int)
    end = begin
    with (directory / (tag + ".csv")).open(newline="") as stream:
        for row in csv.DictReader(stream):
            cycle = int(row["cycle"])
            if cycle <= begin or cycle > measurement_end or row["kind"] != "endpoint":
                continue
            name = row["name"]
            if not name.startswith("LLCH_"):
                continue
            values[name] += int(row["departures"])
            end = max(end, cycle)
    rates = [values["LLCH_{:02d}".format(index)] / measurement_cycles
             for index in range(llch_count)]
    total = sum(rates)
    squares = sum(value * value for value in rates)
    jain = total * total / (llch_count * squares) if squares else 1.0
    mean = total / llch_count
    variance = sum((value - mean) ** 2 for value in rates) / llch_count
    cv = math.sqrt(variance) / mean if mean else 0.0
    return jain, cv, min(rates), max(rates)


def number(row, key):
    return float(row[key])


def main():
    if len(sys.argv) not in (4, 5):
        raise SystemExit("usage: compare_noc16_grants.py RR_DIR WEIGHTED_DIR OUT_DIR [LLCH_COUNT]")
    rr_dir, weighted_dir, out_dir = map(Path, sys.argv[1:4])
    llch_count = int(sys.argv[4]) if len(sys.argv) == 5 else 16
    out_dir.mkdir(parents=True, exist_ok=True)
    policies = {"rr": (rr_dir, load_runs(rr_dir)),
                "weighted": (weighted_dir, load_runs(weighted_dir))}
    keys = sorted(set(policies["rr"][1]) & set(policies["weighted"][1]),
                  key=lambda item: (float(item[0]), int(item[1])))
    fields = ["rate", "seed", "policy", "delivered", "acceptance",
              "network_latency", "packet_latency", "hot_queue_wait",
              "llch_jain", "llch_cv", "llch_min_rate", "llch_max_rate"]
    rows = []
    for rate, seed in keys:
        for policy, (directory, data) in policies.items():
            source = data[(rate, seed)]
            jain, cv, minimum, maximum = llch_fairness(directory, rate, seed, llch_count)
            rows.append({
                "rate": rate, "seed": seed, "policy": policy,
                "delivered": source["delivered_packets_per_cycle"],
                "acceptance": source["acceptance_fraction"],
                "network_latency": source["network_latency"],
                "packet_latency": source["packet_latency"],
                "hot_queue_wait": source["hot_port_queue_wait"],
                "llch_jain": "{:.9f}".format(jain),
                "llch_cv": "{:.9f}".format(cv),
                "llch_min_rate": "{:.9f}".format(minimum),
                "llch_max_rate": "{:.9f}".format(maximum),
            })
    with (out_dir / "runs.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader(); writer.writerows(rows)

    grouped = defaultdict(list)
    for row in rows:
        grouped[(row["rate"], row["policy"])].append(row)
    metrics = ["delivered", "acceptance", "network_latency",
               "packet_latency", "hot_queue_wait", "llch_jain", "llch_cv"]
    summary_fields = ["rate", "policy", "seeds"] + ["mean_" + m for m in metrics]
    summary = []
    for key in sorted(grouped, key=lambda item: (float(item[0]), item[1])):
        samples = grouped[key]
        row = {"rate": key[0], "policy": key[1], "seeds": len(samples)}
        for metric in metrics:
            row["mean_" + metric] = "{:.9f}".format(
                sum(number(sample, metric) for sample in samples) / len(samples))
        summary.append(row)
    with (out_dir / "by_rate.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=summary_fields)
        writer.writeheader(); writer.writerows(summary)

    indexed = {(row["rate"], row["policy"]): row for row in summary}
    delta_fields = ["rate"] + ["weighted_minus_rr_" + metric for metric in metrics]
    deltas = []
    for rate in sorted({key[0] for key in indexed}, key=float):
        if((rate, "rr") not in indexed or (rate, "weighted") not in indexed):
            continue
        row = {"rate": rate}
        for metric in metrics:
            row["weighted_minus_rr_" + metric] = "{:.9f}".format(
                number(indexed[(rate, "weighted")], "mean_" + metric) -
                number(indexed[(rate, "rr")], "mean_" + metric))
        deltas.append(row)
    with (out_dir / "delta_by_rate.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=delta_fields)
        writer.writeheader(); writer.writerows(deltas)


if __name__ == "__main__":
    main()
