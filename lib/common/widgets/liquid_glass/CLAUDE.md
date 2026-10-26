# Liquid glass

Glass panes that bend and magnify what lies behind them, after iOS and
[FlClash](https://github.com/chen08209/FlClash). The 液态玻璃 switch in 外观设置 (`Pref.liquidGlass`, on by default)
turns on every glass part. It only takes effect after a restart.

## How it works

- `LiquidGlassHost` captures what is drawn behind each pane, and the shader in `shaders/liquid_glass.frag` refracts
  that capture. `lib/main.dart` wraps the whole app in `LiquidGlassScope` + `LiquidGlassHost` in its `builder`, so
  glass works on any route or dialog. Don't add another host.
- Refraction needs Impeller's shader filters (`ImageFilter.isShaderFilterSupported`). Without them, as in release
  Android builds and on macOS, panes fall back to frosted blur. Check how a change looks both ways; the Android dev
  flavor has Impeller on.
- A pane's look is a `LiquidGlassStyle`: `regular`, `pill`, `menu`, `alert`, `tinted`, `lens`, `lensContent`.
  `scale(t)` fades a style in, and `lerp` blends two. Menus and alerts also take a `LiquidGlassRim`, iOS's line of
  light around the edge, which `GlassPanel` draws.
- **Dialogs and popup menus** turn to glass without touching their call sites.
  `lib/scripts/material/surface_builders.patch` gives material_ui's `Dialog`, popup menu (with the rect it opens from
  and its route animation), `AlertDialog` actions, `PopupMenuItem` ink, the mark on a menu's current value, the text
  selection toolbar and every `Switch` hooks (`SurfaceBuilders`), and `GlassSurfaces.install()` in `main()` fills them
  while the switch is on, as FlClash's alerts, menus and switches look. `GlassSurfaces.themed` sets their text, spacing and the lighter scrim in `ThemeUtils`. After
  changing the patch, check it still applies after each platform's patch set in `patch.ps1`.
- **Choice rows** (`PopupListTile`, behind every `PopupModel` setting) turn into FlClash's pull-downs with the switch
  on: the value sits at the row's end with an up-down chevron, and the menu opens out of it, its current value
  checked.
- **Call sites with surfaces of their own** (popovers, banners, a framed screenshot) check `GlassSurfaces.installed`
  and draw on `GlassSurfaces.panel` or `GlassSurfaces.pill` instead. Controls that fill themselves, as `iconButton`
  does, ask `GlassSurfaces.onGlass(context)` and fill with `glassFillOf` there.

## Files

| File | Role | Edit? |
| ---- | ---- | ----- |
| `liquid_glass.dart`, `liquid_glass_capture.dart` (part), `shaders/liquid_glass.frag` | Glass core, ported from FlClash (GPL-3.0) | Only with a `// PiliPlus:` comment on each change. Don't reformat |
| `glass_support.dart` | The FlClash helpers the core imports (tone shift, motion, radii, shapes) | Yes |
| `glass_spring.dart` | `GlassSpring`, a retargetable spring that is a `ValueListenable<double>` | Yes |
| `glass_theme.dart` | `floatingGlassShadows`, `glassPlatterColor` | Yes |
| `liquid_glass_button.dart` | A pressable pane: swells and glows under the finger, keyboard focusable | Yes |
| `liquid_glass_tab_bar.dart` | Tabs on a glass pill, with a platter that slides with the pages | Yes |
| `liquid_glass_header.dart` | A header over a soft fade, for content that scrolls under it | Yes |
| `glass_panel.dart` | `GlassPanel`: glass with a rim and a wide shadow, clipping its child, as a menu or alert | Yes |
| `glass_alert_actions.dart` | An alert's buttons as iOS lays them out: capsules, the last one filled, 取消 at the bottom | Yes |
| `glass_switch.dart` | `GlassSwitch`, FlClash's switch: a press lifts the thumb into a lens over the track | Yes |
| `glass_surfaces.dart` | Fills the material_ui hooks: alerts (34 dp, thicker glass, grow in, swell on press), menus (24 dp, rows inset 8), the selection toolbar and switches; `panel`, `pill`, `onGlass` for call sites | Yes |
| `glass_menu_morph.dart` | A menu growing out of its button's capsule into the card, and back into it as it closes | Yes |
| `../liquid_glass_navigation_bar.dart` | The nav bar: a lens you can press, drag and fling | Yes |
| `../header_overlay_inset.dart` | Tells content how much a header laid over it covers | Yes |

## Rules

- **Gate every glass layout on the switch** (`MainController.liquidGlass`, read once). With it off, the page must be
  exactly as before.
- **Glass is for controls floating over content**, as FlClash and iOS use it: bars, buttons, menus, alerts, toasts.
  Bottom sheets and pages are content and stay opaque, and glass never sits on glass.
- **On glass, no ripples.** A pressed row stands on a platter (`highlightColor`), text is `onSurface` or
  `onSurfaceVariant`, and corners are concentric: an inner radius is the outer one less the inset. A platter only
  ever means a press: a menu's current value takes a check at the row's end.
- **Content under an overlaid header** starts with `HeaderOverlayInset.sliver(context)`, or uses
  `HeaderOverlayInset.below(...)` when it pins headers of its own. `RefreshIndicator` reads the inset, so the pull
  indicator comes out from under the header.
- **Motion runs on `GlassSpring`s**, retargeted mid-flight, not on fixed curves. Respect
  `MediaQuery.disableAnimationsOf` by jumping instead of springing.
- **Interactive glass** keeps keyboard focus and activation (`FocusableActionDetector` + `ActivateIntent`), shows a
  ring while focused, and carries `Semantics`.
- **Size from layout, not constants.** Pointer and lens maths use the width the widget actually got
  (`LayoutBuilder`), since narrow windows squeeze it.

## Testing

Glass only refracts under Impeller, so render tests run with `flutter test --enable-impeller`:

- Draw inside a `RepaintBoundary` and grab it with `toImage()` in `tester.runAsync`.
- Load real fonts with `FontLoader`, or text renders as boxes.
- Wrap the tree in `LiquidGlassScope(enabled: true)` + `LiquidGlassHost(enabled: true)`.

Code that calls `feedBack()` needs `enableFeedback = false` in the test.

Put throwaway render tests in a scratch folder rather than `test/`.
