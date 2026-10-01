#!/usr/bin/env python3
"""Summarize profile-idle.c CSV; the first row is a cumulative baseline."""
import csv
import json
import math
import sys

with open(sys.argv[1], newline="") as source:
    rows = list(csv.DictReader(source))
if len(rows) < 2:
    raise SystemExit("Need a baseline and at least one interval")
first, last = rows[0], rows[-1]


def delta(field):
    value = float(last[field]) - float(first[field])
    if value < 0:
        raise SystemExit(f"Counter went backwards: {field}")
    return value


elapsed = delta("active_seconds")
if elapsed <= 0:
    raise SystemExit("Invalid measurement duration")
cpu = [float(row["cpu_percent"]) for row in rows[1:]]
footprints = [int(row["footprint_bytes"]) / 2**20 for row in rows]
resident = [int(row["resident_bytes"]) / 2**20 for row in rows]
gaps = [float(b["active_seconds"]) - float(a["active_seconds"])
        for a, b in zip(rows, rows[1:])]
print(json.dumps({
    "start_utc": first["utc"], "end_utc": last["utc"],
    "active_seconds": elapsed, "continuous_seconds": delta("continuous_seconds"),
    "sample_intervals": len(cpu), "longest_interval_seconds": max(gaps),
    "cpu_seconds": delta("cpu_seconds"),
    "mean_cpu_percent": 100 * delta("cpu_seconds") / elapsed,
    "max_interval_cpu_percent": max(cpu),
    "p95_interval_cpu_percent": sorted(cpu)[math.ceil(len(cpu) * .95) - 1],
    "samples_rounding_to_0_0_percent": sum(f"{value:.1f}" == "0.0" for value in cpu),
    "footprint_mib_range": [min(footprints), max(footprints)],
    "resident_mib_range": [min(resident), max(resident)],
    "interrupt_wakeups": int(delta("interrupt_wakeups")),
    "package_idle_wakeups": int(delta("package_idle_wakeups")),
    "disk_read_bytes": int(delta("disk_read_bytes")),
    "disk_written_bytes": int(delta("disk_written_bytes")),
}, indent=2))
