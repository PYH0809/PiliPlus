run `dart run tool/jnigen.dart`

## Measuring on a phone

Both scripts drive a profile build (`flutter run --profile > run.log`)
through its `ext.piliplus.*` debug commands (`lib/utils/debug_commands.dart`),
which release builds leave out. They need adb and nothing else on the phone.

- `measure_glass.py`: the player's glass over the video, case by case.
- `measure_scroll.py`: what dragging the open page costs a frame. Open the
  page first, then `python3 tool/measure_scroll.py run.log <label>`.

What each one reads:

| Numbers | Needs |
| ------- | ----- |
| Frames drawn, fps, UI and raster times (FrameStats, from `resetFrames` on) | adb |
| Frames the screen showed late (SurfaceFlinger's present times; `dumpsys gfxinfo` counts none, as Flutter draws into a SurfaceView) | adb |
| GPU busy time a frame (kgsl `gpubusy`) | root |
| `--pin`: the GPU held at 427 MHz and the display at 90 Hz while measuring, put back after | root |

Without root, `measure_scroll.py` says the GPU numbers are left out and
measures the rest. The GPU's clock follows its load, so without `--pin` a
change can move the clock rather than the busy time: compare pinned numbers.
The pins are a OnePlus 7 Pro's (Adreno 640, a 90 Hz panel); another phone
has other power levels and display configs.
