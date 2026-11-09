#!/usr/bin/env python3
"""Capture actual Pulse and macOS readings together; retain denied commands as errors."""
import concurrent.futures
import datetime
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(command):
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
        return {"command": command, "start": start, "end": datetime.datetime.now(datetime.timezone.utc).isoformat(), "exit": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
    except OSError as error:
        return {"command": command, "start": start, "error": str(error)}

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    pulse = pool.submit(run, [str(ROOT / "build/Pulse.app/Contents/MacOS/Pulse"), "--dump-json"])
    top = pool.submit(run, ["/usr/bin/top", "-l", "2", "-n", "0"])
    time.sleep(1.9)
    commands = [run(c) for c in [["/usr/sbin/sysctl", "vm.swapusage"], ["/usr/bin/memory_pressure"], ["/bin/df", "-k", "/"], ["/usr/sbin/ioreg", "-c", "IOBlockStorageDriver", "-r", "-w0"]]]
    result = {"pulse": pulse.result(), "top": top.result(), "system": commands}
try:
    app = json.loads(result["pulse"]["stdout"])
    free = re.search(r"System-wide memory free percentage: (\d+)%", commands[1]["stdout"])
    df = commands[2]["stdout"].splitlines()[-1].split()
    writes = sum(int(x) for x in re.findall(r'"Bytes \(Write\)"=(\d+)', commands[3]["stdout"]))
    result["comparisons"] = {
        "memoryFreePercent": {"pulse": app.get("memoryFreePercent"), "system": int(free[1]) if free else None, "tolerance_points": 5},
        "diskFree": {"pulse": app.get("diskFree"), "system": int(df[3]) * 1024, "tolerance_bytes": 1_000_000_000},
        "bytesWritten": {"pulse": app.get("bytesWritten"), "system": writes, "tolerance_bytes": 0},
        "swap": {"pulse": app.get("swap"), "system": commands[0].get("stderr")},
        "cpu": {"pulse": app.get("cpu"), "system": result["top"].get("error", result["top"].get("stderr"))}
    }
except (KeyError, ValueError, IndexError) as error:
    result["comparison_error"] = str(error)
print(json.dumps(result, indent=2))
