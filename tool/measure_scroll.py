"""Measure what scrolling the page open in the app costs a frame, on an
Android phone over adb, through the app's debug commands.

Run the app in profile mode, its output to a file, open the page to measure,
then:

    python3 tool/measure_scroll.py run.log [label] [--rounds N] [--pin]

Each round drags the page up and then down, 1.2 s each, through the
middle of the screen, and measures 1.7 s from the first frame the drag
draws, the fling after it with it: `input swipe` lets go moving. Frames a
page draws by itself, as an animated picture's, fall outside that. For each
drag it prints the frames the app drew, their fps and mean UI and raster
times (FrameStats' frame log), and the frames the screen showed a refresh
or more late (SurfaceFlinger's present times for the app's surface, against
its refresh period, as `dumpsys gfxinfo` counts none: Flutter draws into a
SurfaceView). A drag that reaches an end of the page stands still for the
rest of the window, and its gaps count as late: give it room to scroll. If
the display changed its rate within the drag, the late count reads ?, as no
one period judges it.

With root (`su`) on a Qualcomm GPU, it also prints how busy the GPU was over
each drag, from kgsl (`/sys/class/kgsl/kgsl-3d0/gpubusy`). That answers the
busy and total time of the driver's last window, about a second, so it is
read through the drag, and the windows from its start to the first that
comes out after the window ends are summed: they reach up to a second past
either end, which dilutes the busy share a little alike for every build.
The GPU's clock follows its load, so --pin holds it at 427 MHz and the
display at 90 Hz while measuring (a OnePlus 7 Pro's), and after puts back
the GPU's levels and lets go of the display. SurfaceFlinger answers no
forced display config to put back, so a config forced before the run is
lost: it says so as it lets go. Without root or kgsl those numbers are left
out, and it says so. --surface names the app's SurfaceFlinger layer, when
the one it finds is not it.

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
import threading
import time
import urllib.parse
import urllib.request

PACKAGE = "com.example.piliplus"
# The app's SurfaceFlinger layer; found by surface() unless --surface names it.
SURFACE = None
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


def has_kgsl():
    # Without su this fails, as expected; with it, a phone without a
    # Qualcomm GPU has no kgsl.
    return "ok" in adb_shell(f"su -c 'test -r {KGSL}/gpubusy && echo ok' 2>/dev/null", check=False)


def surface():
    """The app's SurfaceView layer, named as this Android names it: of the
    layers so named, as Android 12's container and its BLAST buffer layer,
    the one that has shown frames."""
    for line in adb_shell("dumpsys SurfaceFlinger --list").split("\n"):
        name = line.strip()
        if name.startswith("SurfaceView") and PACKAGE in name:
            if presents(required=False, layer=name)[1]:
                return name
    sys.exit(f"no SurfaceView layer of {PACKAGE}: is the app in front? (--surface names it)")


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


def presents(required=True, layer=None):
    """The display's refresh period and the app surface's present times
    SurfaceFlinger holds, in ns."""
    period, times = None, []
    layer = layer or SURFACE
    for line in adb_shell(f'dumpsys SurfaceFlinger --latency "{layer}"').split("\n"):
        parts = line.split()
        if not parts or not all(p.isdigit() for p in parts):
            continue
        if len(parts) == 1 and period is None:
            period = int(parts[0])
        elif len(parts) == 3 and 0 < int(parts[1]) < 2**62:
            times.append(int(parts[1]))
    if required and (not period or not times):
        sys.exit(f"SurfaceFlinger holds no frames for {layer!r}: is the app in front?")
    return period, times


# The drag, and the fling after it, are measured over this long from the
# first frame it draws: frames a page draws by itself, as an animated
# picture's, would otherwise keep a measurement going.
DRAG_S = 1.2
WINDOW_NS = int((DRAG_S + 0.5) * 1e9)


def late(period, times):
    """Frames shown a refresh or more after the one before them, among
    frames shown while the page moved, every vsync."""
    return sum(1 for a, b in zip(times, times[1:]) if b - a > period * 1.5)


class GpuBusy:
    """kgsl's busy and total time of the driver's last window, about a
    second, sampled in the background with when each came in."""

    def __init__(self):
        serial = ["-s", SERIAL] if SERIAL else []
        self.windows = []
        self._process = subprocess.Popen(
            ["adb", *serial, "shell",
             # Bounded, should the phone's shell outlive adb's.
             f"su -c 'for i in $(seq 40); do cat {KGSL}/gpubusy; sleep 0.25; done'"],
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _read(self):
        for line in self._process.stdout:
            parts = line.split()
            if len(parts) == 2 and (not self.windows or self.windows[-1][1] != parts):
                self.windows.append((time.time(), parts))

    def share(self, start, end):
        """The busy share of the windows that came out after [start] up to
        the first after [end], which holds it; None without that one."""
        deadline = time.time() + 2.5
        while time.time() < deadline and not any(t >= end for t, _ in self.windows):
            time.sleep(0.1)
        self._process.terminate()
        kept = []
        for at, (busy, total) in self.windows:
            if at > start:
                kept.append((int(busy), int(total)))
            if at >= end:
                break
        else:
            return None
        return sum(b for b, _ in kept) / max(sum(t for _, t in kept), 1)


def screen_size():
    """The screen's size in pixels as it is turned now, as input takes it."""
    size = re.search(r"cur=(\d+)x(\d+)", adb_shell("dumpsys window displays"))
    if not size:
        sys.exit("dumpsys window displays answered no current size")
    return int(size[1]), int(size[2])


def drag(app, start, end, root):
    """Drags from [start] to [end], shares of the screen's height."""
    width, height = screen_size()
    app.ext("resetFrames")
    adb_shell(f'dumpsys SurfaceFlinger --latency-clear "{SURFACE}"')
    gpu = GpuBusy() if root else None
    began = time.time()
    # SurfaceFlinger keeps the last 128 or so: read them as the drag goes.
    serial = ["-s", SERIAL] if SERIAL else []
    swipe = subprocess.Popen(
        ["adb", *serial, "shell",
         f"input swipe {width // 2} {int(start * height)} {width // 2} "
         f"{int(end * height)} {int(DRAG_S * 1000)}"]
    )
    periods, shown = set(), set()

    def read_presents():
        period, times = presents(required=False)
        periods.add(period)
        shown.update(times)

    while swipe.poll() is None:
        time.sleep(0.5)
        read_presents()
    if swipe.returncode != 0:
        sys.exit(f"input swipe failed: {swipe.returncode}")
    # The window counts from the first frame, which comes a little after
    # the command: read on past its end, as frame timings, which come in
    # batches at least once a second, take that long anyway.
    ended = began + DRAG_S + 0.5 + 0.5
    while time.time() < ended + 0.6:
        time.sleep(0.4)
        read_presents()
    # [raster finish us, raster ms, UI ms] a frame, on SurfaceFlinger's clock.
    log = json.loads(app.ext("frameLog"))
    first = log[0][0] * 1000 if log else 0
    frames = [f for f in log if f[0] * 1000 - first <= WINDOW_NS]
    shown = sorted(t for t in shown if first <= t <= first + WINDOW_NS)
    span = (frames[-1][0] - frames[0][0]) / 1e6 if len(frames) > 1 else 0
    periods.discard(None)
    return {
        "frames": len(frames),
        "fps": (len(frames) - 1) / span if span else 0,
        "raster": statistics.mean(f[1] for f in frames) if frames else 0,
        "ui": statistics.mean(f[2] for f in frames) if frames else 0,
        # Unpinned, the display may change its rate within the drag, which
        # leaves no one period to judge the gaps by.
        "late": late(periods.pop(), shown) if len(periods) == 1 else None,
        "gpu": gpu.share(began, ended) if gpu else None,
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
            f"echo {PINNED_LEVEL} > {KGSL}/max_pwrlevel && "
            f"echo {PINNED_LEVEL} > {KGSL}/min_pwrlevel && "
            f"service call SurfaceFlinger {FORCE_CONFIG} i32 {NINETY_HZ_CONFIG}"
        )

    def undo():
        # Every step, whichever fails, then say which did.
        failed = []
        for step in (
            f"echo {levels[0]} > {KGSL}/min_pwrlevel",
            f"echo {levels[1]} > {KGSL}/max_pwrlevel",
            f"service call SurfaceFlinger {FORCE_CONFIG} i32 -1",
        ):
            try:
                done = "ok" in adb_shell(f"su -c '{step} && echo ok'", check=False)
            except subprocess.TimeoutExpired:
                done = False
            if not done:
                failed.append(step)
        if failed:
            print(f"could not undo: {failed}; put them back by hand", flush=True)
        print(
            "let go of the display's forced config: one forced before the run "
            f"is lost (service call SurfaceFlinger {FORCE_CONFIG} i32 <index> sets it)",
            flush=True,
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
    parser.add_argument("--surface", help="the app's SurfaceFlinger layer")
    args = parser.parse_args()
    app = App(args.log)
    global SURFACE
    SURFACE = args.surface or surface()
    # The app's surface is there, with frames from before.
    presents()
    root = has_kgsl()
    if not root:
        if args.pin:
            sys.exit("--pin needs root and a Qualcomm GPU's kgsl")
        print("no root or no kgsl: GPU busy time is left out", flush=True)
    pin, undo = pinning() if root and args.pin else (None, None)
    try:
        if pin:
            pin()
        drags = []
        for _ in range(args.rounds):
            drags.append(("up", drag(app, 0.74, 0.22, root)))
            drags.append(("down", drag(app, 0.22, 0.74, root)))
    finally:
        if undo:
            undo()
    for way in ("up", "down"):
        # A drag the page could not follow, at an end of it, drew no frames.
        runs = [d for w, d in drags if w == way and d["frames"] >= 2]
        busy = [r["gpu"] for r in runs if r["gpu"] is not None]
        if not runs:
            print(f"{args.label} {way:4}: no frames drawn; is there room to scroll?")
            continue
        line = (
            f"{args.label} {way:4}: frames {[r['frames'] for r in runs]}"
            f"  fps {statistics.median(r['fps'] for r in runs):4.1f}"
            f"  UI {statistics.median(r['ui'] for r in runs):4.1f} ms"
            f"  raster {statistics.median(r['raster'] for r in runs):4.1f} ms"
            f"  late {['?' if r['late'] is None else r['late'] for r in runs]}"
        )
        if busy:
            line += f"  GPU busy {100 * statistics.median(busy):3.0f}%"
        print(line, flush=True)
    if any(d["late"] is None for _, d in drags):
        print("late ?: the display changed its rate within the drag; --pin holds it")
    print(f"battery {temperature()} °C", flush=True)


if __name__ == "__main__":
    main()
