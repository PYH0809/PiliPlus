"""Measure what scrolling the page open in the app costs a frame, on an
Android phone over adb, through the app's debug commands.

Run the app in profile mode, its output to a file, open the page to measure,
then:

    python3 tool/measure_scroll.py run.log [label] [--rounds N] [--pin]

Each round drags the page up and then down, 1.2 s each with the finger held,
so it never flings, in the middle of a 1440x3120 screen. For each drag it
prints the frames the app drew, their fps and mean raster time (FrameStats),
and the frames the screen showed late (SurfaceFlinger's present times for
the app's surface, as `dumpsys gfxinfo` counts none: Flutter draws into a
SurfaceView).

With root (`su`), it also reads the GPU's busy time from kgsl
(`/sys/class/kgsl/kgsl-3d0/gpubusy`) over each drag, and prints it per frame
drawn. The GPU's clock follows its load, so --pin holds it at 427 MHz and
the display at 90 Hz while measuring, and puts both back after. Without
root those numbers are left out, and it says so.

Interleave the builds or switches you compare, a few rounds each, and note
the temperature it prints: a warm phone slows every one. ANDROID_SERIAL
picks the device when more than one is attached.
"""

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import time
import urllib.parse
import urllib.request

PACKAGE = "com.example.piliplus"
SURFACE = f"SurfaceView - {PACKAGE}/{PACKAGE}.MainActivity#0"
KGSL = "/sys/class/kgsl/kgsl-3d0"
# kgsl's power level 2 is 427 MHz on an Adreno 640; the governor follows the
# load between its min_pwrlevel and max_pwrlevel.
PINNED_LEVEL = "2"
# SurfaceFlinger's debug code to force a display config, by its 0-based
# index: 1 is 1440x3120 at 90 Hz on a OnePlus 7 Pro; -1 lets go of it.
FORCE_CONFIG = 1035
NINETY_HZ_CONFIG = "1"
SERIAL = os.environ.get("ANDROID_SERIAL")


def adb_shell(command, timeout=30, check=True):
    serial = ["-s", SERIAL] if SERIAL else []
    done = subprocess.run(
        ["adb", *serial, "shell", command],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if check and done.returncode != 0:
        sys.exit(f"adb shell {command!r} failed: {done.stderr.strip() or done.returncode}")
    return done.stdout


def su(command):
    return adb_shell(f"su -c '{command}'")


def has_root():
    # Without su this fails, as expected.
    return "uid=0" in adb_shell("su -c id 2>/dev/null", check=False)


class App:
    def __init__(self, log):
        # The log of flutter run, or the VM service's URL itself.
        text = log if log.startswith("http") else open(log).read()
        urls = re.findall(r"http://127\.0\.0\.1:\d+/[^/ ]+=/", text)
        if not urls:
            sys.exit(f"no VM service URL in {log}: is flutter run up?")
        self.url = urls[-1]
        vm = self.call("getVM")
        self.isolate = next(i["id"] for i in vm["isolates"] if "main" in i["name"])

    def call(self, method, **params):
        query = urllib.parse.urlencode(params)
        with urllib.request.urlopen(f"{self.url}{method}?{query}", timeout=10) as r:
            body = json.load(r)
        if "error" in body:
            sys.exit(f"{method}: {body['error']}")
        return body["result"]

    def ext(self, name):
        return self.call(f"ext.piliplus.{name}", isolateId=self.isolate)["result"]


def presents():
    """The app surface's present times SurfaceFlinger holds, in ns."""
    times = []
    for line in adb_shell(f'dumpsys SurfaceFlinger --latency "{SURFACE}"').split("\n"):
        parts = line.split()
        if len(parts) == 3 and all(p.isdigit() for p in parts) and 0 < int(parts[1]) < 2**62:
            times.append(int(parts[1]))
    if not times:
        sys.exit(f"SurfaceFlinger holds no frames for {SURFACE!r}: is the app in front?")
    return times


def late(times):
    gaps = [b - a for a, b in zip(times, times[1:])]
    if not gaps:
        return 0
    usual = sorted(gaps)[len(gaps) // 2]
    return sum(1 for gap in gaps if gap > usual * 1.5)


def drag(app, start, end, root):
    app.ext("resetFrames")
    adb_shell("dumpsys SurfaceFlinger --latency-clear")
    swipe = f"input swipe 720 {start} 720 {end} 1200"
    busy = None
    if root:
        out = su(f"cat {KGSL}/gpubusy >/dev/null; {swipe}; cat {KGSL}/gpubusy").split()
        busy = int(out[0]) / 1000
    else:
        adb_shell(swipe)
    # Frame timings come in batches: wait till the count stops growing.
    frames, deadline = {}, time.time() + 3
    while time.time() < deadline:
        time.sleep(0.4)
        last = frames.get("frames", 0)
        frames = json.loads(app.ext("state"))["frames"] or {}
        if frames.get("frames", 0) == last and last > 0:
            break
    count = frames.get("frames", 0)
    return {
        "frames": count,
        "fps": frames.get("fps", 0),
        "raster": frames.get("rasterMean", 0),
        "late": late(presents()),
        "gpu": busy / count if busy is not None and count else None,
    }


def temperature():
    for line in adb_shell("dumpsys battery").split("\n"):
        if "temperature" in line:
            return int(line.split(":")[1]) / 10
    return None


def pinning():
    """How to pin the GPU's clock and the display's rate, and to undo it."""
    levels = su(f"cat {KGSL}/min_pwrlevel {KGSL}/max_pwrlevel").split()

    def pin():
        su(
            f"echo {PINNED_LEVEL} > {KGSL}/max_pwrlevel; "
            f"echo {PINNED_LEVEL} > {KGSL}/min_pwrlevel; "
            f"service call SurfaceFlinger {FORCE_CONFIG} i32 {NINETY_HZ_CONFIG}"
        )

    def undo():
        su(
            f"echo {levels[0]} > {KGSL}/min_pwrlevel; "
            f"echo {levels[1]} > {KGSL}/max_pwrlevel; "
            f"service call SurfaceFlinger {FORCE_CONFIG} i32 -1"
        )

    return pin, undo


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("log", help="flutter run --profile's output, or its VM URL")
    parser.add_argument("label", nargs="?", default="scroll")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--pin", action="store_true", help="root: 427 MHz, 90 Hz")
    args = parser.parse_args()
    app = App(args.log)
    root = has_root()
    if not root:
        print("no root: GPU busy time and the pins are left out", flush=True)
    pin, undo = pinning() if root and args.pin else (None, None)
    try:
        if pin:
            pin()
        drags = []
        for _ in range(args.rounds):
            drags.append(("up", drag(app, 2300, 700, root)))
            drags.append(("down", drag(app, 700, 2300, root)))
    finally:
        if undo:
            undo()
    for way in ("up", "down"):
        runs = [d for w, d in drags if w == way]
        line = (
            f"{args.label} {way:4}: fps {statistics.median(r['fps'] for r in runs):4.1f}"
            f"  raster {statistics.median(r['raster'] for r in runs):4.1f} ms"
            f"  late {[r['late'] for r in runs]}"
        )
        if root:
            line += f"  GPU {statistics.median(r['gpu'] for r in runs):4.1f} ms a frame"
        print(line, flush=True)
    print(f"battery {temperature()} °C", flush=True)


if __name__ == "__main__":
    main()
