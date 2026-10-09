#!/usr/bin/env python3
"""Glitch-Overview's resource readout: each window's CPU and memory, with the
processes it started, as a JSON line every ~1.5 s until stopped.

    {"windows": {"0xADDRESS": {"cpu": percent, "mem": bytes, "procs": n}}, "cpu": total%, "mem": total}

CPU is percent of one core over the last interval (so a busy window can
show more than 100); memory is resident set size.
"""
import json
import os
import subprocess
import sys
import time

TICK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")


def procs():
    """pid -> (ppid, cpu ticks, rss bytes) for every process"""
    out = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                s = f.read()
            rest = s[s.rindex(")") + 2:].split()
            ppid, ticks = int(rest[1]), int(rest[11]) + int(rest[12])
            with open(f"/proc/{d}/statm") as f:
                rss = int(f.read().split()[1]) * PAGE
            out[int(d)] = (ppid, ticks, rss)
        except (OSError, ValueError, IndexError):
            pass
    return out


def main():
    last, last_t = {}, None
    while True:
        try:
            clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3).stdout)
        except Exception:
            clients = []
        table = procs()
        kids = {}
        for pid, (ppid, _, _) in table.items():
            kids.setdefault(ppid, []).append(pid)
        now = time.monotonic()
        dt = (now - last_t) if last_t else None
        windows, cur, tot_cpu, tot_mem, seen = {}, {}, 0.0, 0, set()
        for c in clients:
            pid = c.get("pid", -1)
            if pid <= 0 or pid not in table:
                continue
            tree, stack = [], [pid]
            while stack:                                # the window's process and its children
                p = stack.pop()
                tree.append(p)
                stack.extend(kids.get(p, []))
            ticks = sum(table[p][1] for p in tree)
            mem = sum(table[p][2] for p in tree)
            cur[pid] = ticks
            cpu = 0.0
            if dt and pid in last:
                cpu = max(0.0, (ticks - last[pid]) / TICK / dt * 100)
            windows[c["address"]] = {"cpu": round(cpu, 1), "mem": mem, "procs": len(tree)}
            if pid not in seen:                         # several windows can share a process
                seen.add(pid)
                tot_cpu += cpu
                tot_mem += mem
        last, last_t = cur, now
        print(json.dumps({"windows": windows, "cpu": round(tot_cpu, 1), "mem": tot_mem}), flush=True)
        time.sleep(1.5)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
