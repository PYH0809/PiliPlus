"""Measure the player's glass on a phone through the app's debug commands.

Run the app in profile mode, its output to a file:

    flutter run --profile -d <device> --android-project-arg dev=1 > run.log

turn on 显示性能浮层 in the app once, then:

    python3 tool/measure_glass.py run.log [true|false] <case> [<case> ...]

true or false shows danmaku or not (default false: danmaku cost frames of
their own). A case is mode:layout[:extra...]: mode refract, frost or tint;
layout full or portrait; extras hidden (the controls out of sight), notesoff
(the small notes only tint), trace (list the UI thread's time by
event), panel
(full screen, open the ⋮ side panel) and scroll (portrait, scroll the page
under the player and switch its tabs). Each prints the raster and UI times
of a frame drawn every vsync for 3 s, as the video's every new frame redraws
the screen, and saves a screenshot as glass_<case>.png.

Every step checks the app reached the state it asked for within a few
seconds; a case that does not fails with what it was waiting for. The taps
for panel and scroll assume a 1440x3120 screen. ANDROID_SERIAL picks the
device when more than one is attached.
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

PACKAGE = "com.example.piliplus"
VIDEO = "https://www.bilibili.com/video/BV1GJ411x7h7"
MODES = {"refract": 0, "frost": 1, "tint": 2}
SERIAL = os.environ.get("ANDROID_SERIAL")

URL = None
ISOLATE = None


class Failed(Exception):
    pass


def adb(*args):
    serial = ["-s", SERIAL] if SERIAL else []
    subprocess.run(["adb", *serial, *args], check=True, capture_output=True, timeout=20)


def vm_url(log):
    urls = re.findall(r"http://127\.0\.0\.1:\d+/[^/ ]+=/", open(log).read())
    if not urls:
        raise Failed(f"no VM service URL in {log}: is flutter run up?")
    return urls[-1]


def call(method, **params):
    # The app's commands run in its isolate; the VM's own methods take none.
    if ISOLATE and method.startswith("ext."):
        params = {"isolateId": ISOLATE, **params}
    query = urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(f"{URL}{method}?{query}", timeout=5) as response:
            body = json.load(response)
    except Exception as e:
        raise Failed(f"{method}: {e}") from e
    if "error" in body:
        raise Failed(f"{method}: {body['error']}")
    return body["result"]


def ext(name, **params):
    return call(f"ext.piliplus.{name}", **params)["result"]


def state():
    return json.loads(ext("state"))


def wait(what, check, timeout):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = state()
        if check(last):
            return last
        time.sleep(0.5)
    raise Failed(f"timed out after {timeout}s waiting for {what}; last state {last}")


def foreground():
    # Commands queue but do not run while the app is in the background.
    adb("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity")
    time.sleep(1)


def leave_video():
    # Back out of any panel, full screen and the video page, to the page
    # the video opens from; never past it, which would quit the app.
    for _ in range(4):
        s = state()
        if s["route"] != "/videoV":
            return
        if s["fullscreen"]:
            ext("fullscreen", on="false")
            wait("leaving full screen", lambda s: not s["fullscreen"], 5)
        else:
            adb("shell", "input", "keyevent", "BACK")
            time.sleep(1.5)
    raise Failed(f"still on the video page: {state()}")


def screenshot(name):
    adb("shell", "screencap", "-p", "/sdcard/glass.png")
    adb("pull", "/sdcard/glass.png", f"glass_{name.replace(':', '_')}.png")


def describe(f):
    if not f:
        return "no frames"
    return (
        f"raster {f['rasterMean']:.1f} / worst {f['rasterWorst']:.1f} ms, "
        f"ui {f['uiMean']:.1f} / {f['uiWorst']:.1f} ms, {f['fps']:.0f} fps, "
        f"{f.get('dropped', '?')} late of {f['frames']} frames"
    )


def print_ui_time(events):
    # What the UI thread spent its time on, by event, the longest first.
    ui = {e["tid"] for e in events if e.get("ph") == "M" and e.get("args", {}).get("name", "").startswith("1.ui")}
    totals, open_ = {}, {}
    for e in events:
        if e.get("tid") not in ui:
            continue
        name, ph = e.get("name"), e.get("ph")
        if ph == "X":
            totals[name] = totals.get(name, 0) + e.get("dur", 0)
        elif ph == "B":
            open_.setdefault((e["tid"], name), []).append(e["ts"])
        elif ph == "E" and open_.get((e["tid"], name)):
            totals[name] = totals.get(name, 0) + e["ts"] - open_[(e["tid"], name)].pop()
    for name, us in sorted(totals.items(), key=lambda kv: -kv[1])[:12]:
        print(f"    {us / 1000:8.1f} ms  {name}", flush=True)
    # The raster thread: how many offscreen layers and render passes a
    # frame takes, each a pass the GPU starts and stores apart.
    raster = {e["tid"] for e in events if e.get("ph") == "M" and e.get("args", {}).get("name", "").startswith("1.raster")}
    counts = {}
    for e in events:
        if e.get("tid") in raster and e.get("ph") in ("B", "X"):
            counts[e["name"]] = counts.get(e["name"], 0) + 1
    frames = max(counts.get("Rasterizer::DrawToSurfaces", 0), 1)
    print(f"    raster: {frames} frames", flush=True)
    for name in ("Canvas::saveLayer", "Canvas::FlipBackdrop", "RenderPassGLES::EncodeCommandsInReactor"):
        print(f"    {counts.get(name, 0) / frames:8.1f} a frame  {name}", flush=True)


def measure(case):
    mode, layout, *rest = case.split(":")
    panel = "panel" in rest
    scroll = "scroll" in rest
    foreground()
    leave_video()
    ext("setting", key="videoGlassMode", value=str(MODES[mode]))
    ext("setting", key="videoGlassNotes", value=json.dumps("notesoff" not in rest))
    ext("open", url=VIDEO)
    # Loading the video over the network takes the longest.
    wait("the video to play", lambda s: s["playing"], 15)
    start = state()["position"]
    wait("playback to advance", lambda s: s["position"] > start, 5)
    if layout == "full":
        ext("fullscreen", on="true")
        wait("full screen", lambda s: s["fullscreen"], 5)
    shown = "hidden" not in rest
    ext("controls", on=json.dumps(shown))
    wait("the controls", lambda s: s["controls"] == shown, 5)
    time.sleep(2)
    if panel:
        # The ⋮ at the top right opens the side panel: count the frames of
        # its slide in, then of the panel standing open.
        ext("resetFrames")
        adb("shell", "input", "tap", "2964", "108")
        time.sleep(1.2)
        print(f"  opening the panel: {describe(state()['frames'])}", flush=True)
        screenshot(f"{case}_opening")
    trace = "trace" in rest
    if trace:
        call("clearVMTimeline")
        call("setVMTimelineFlags", recordedStreams="[Dart,Embedder]")
    ext("resetFrames")
    # Every vsync, as the video's every new frame redraws the screen, which
    # the overlay does not count by itself.
    forced = threading.Thread(target=lambda: ext("frames", seconds="4" if scroll else "3"))
    forced.start()
    if scroll:
        # Under the player, as the controls show: scroll the page, switch to
        # the comments and back.
        adb(
            "shell",
            "input swipe 720 2700 720 1500 250; sleep 0.4; input swipe 720 1500 720 2700 250; "
            "sleep 0.4; input tap 820 1048; sleep 0.8; input swipe 720 2700 720 1500 250; "
            "sleep 0.4; input tap 440 1048",
        )
    forced.join(timeout=8)
    s = state()
    if trace:
        print_ui_time(call("getVMTimeline")["traceEvents"])
        call("setVMTimelineFlags", recordedStreams="[]")
    if not s["playing"] or (s["frames"] or {}).get("frames", 0) < 120:
        raise Failed(f"counted too little: {s}")
    if layout == "full" and not s["fullscreen"]:
        raise Failed(f"left full screen while measuring: {s}")
    screenshot(case)
    return s


def main():
    global URL, ISOLATE
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    URL = vm_url(sys.argv[1])
    ISOLATE = next(i["id"] for i in call("getVM")["isolates"] if "main" in i["name"])
    args = sys.argv[2:]
    danmaku = args.pop(0) if args[0] in ("true", "false") else "false"
    foreground()
    ext("setting", key="autoPlayEnable", value="true")
    ext("setting", key="enableShowDanmaku", value=danmaku)
    for case in args:
        try:
            s = measure(case)
        except Failed as e:
            print(f"{case}: FAILED {e}", flush=True)
            continue
        print(f"{case}: {describe(s['frames'])}", flush=True)


if __name__ == "__main__":
    main()
