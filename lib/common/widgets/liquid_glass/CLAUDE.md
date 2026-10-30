# Liquid glass

Glass panes that bend and magnify what lies behind them, after iOS and
[FlClash](https://github.com/chen08209/FlClash). The 液态玻璃 switch in 外观设置 (`Pref.liquidGlass`, on by default)
turns on every glass part. It only takes effect after a restart.

## How it works

- `LiquidGlassHost` captures what is drawn behind each pane, and the shader in `shaders/liquid_glass.frag` refracts
  that capture. `lib/main.dart` wraps the whole app in `LiquidGlassScope` + `LiquidGlassHost` in its `builder`, so
  glass works on any route or dialog. Don't add another host.
- Refraction needs Impeller's shader filters (`ImageFilter.isShaderFilterSupported`). Without them, as in release
  Android builds and on macOS, panes fall back to a thickened tint with a rim, not a blur. Check how a change looks
  both ways; the Android dev flavor has Impeller on.
- **Without Impeller, what holds still draws from images** (`liquid_glass_skia.dart`): Flutter hands Skia a new path
  every frame, so Skia would mask and blur every pane's shadows and stroke its rims again each frame. A pane's
  shadows go into a layer of their own, which the host lays on whole device pixels, and the frost's rims into the
  pane's capture, each drawn once into an image after two frames asking for the same, so a pane on the move keeps its
  paths. The tint stays a path, and so do the rims of a pane with a `LiquidGlassRim`, whose shine adds its light.
  `ext.piliplus.glassImages?on=` turns it on or off to measure.
- **Over the video** the host sees nothing: the video is a texture, not a picture it can replay. `VideoGlass` is a
  backdrop filter instead: an engine blur, shared by the panes of a `BackdropGroup`, and nested in it the glass
  shader, which bends and tints the blur (`liquidGlassProgram`, `liquidGlassLook`). Without shader filters it
  frosts. It is dark in either theme, as the player's icons are white; `VideoGlass.controlsTheme` gives the
  controls on it a dark theme, so their menus read dark too. A translucent `Opacity` above a backdrop filter breaks
  it, so it eases in through its `t`, never a fade; `VideoGlassHidden` turns it off while the controls are out of
  sight.
- A pane's look is a `LiquidGlassStyle`: `regular`, `pill`, `menu`, `alert`, `tinted`, `lens`, `lensContent`.
  `scale(t)` fades a style in, and `lerp` blends two. Menus and alerts also take a `LiquidGlassRim`, iOS's line of
  light around the edge, which `GlassPanel` draws.
- **Dialogs and popup menus** turn to glass without touching their call sites.
  `lib/scripts/material/surface_builders.patch` gives material_ui's `Dialog`, popup menu (with the rect it opens from
  and its route animation), `AlertDialog` actions, `PopupMenuItem` ink, the mark on a menu's current value, the text
  selection toolbar, every `Switch` and every `PopupMenuButton`'s press hooks (`SurfaceBuilders`), and
  `GlassSurfaces.install()` in `main()` fills them while the switch is on, as FlClash's alerts, menus and switches
  look. `GlassSurfaces.themed` sets their text, spacing and the lighter scrim in `ThemeUtils`. After changing the
  patch, check it still applies after each platform's patch set in `patch.ps1`.
- **Choice rows** (`PopupListTile`, behind every `PopupModel` setting) turn into FlClash's pull-downs with the switch
  on: the value sits at the row's end with an up-down chevron, and the menu opens out of it, its current value
  checked.
- **A menu takes its button in and gives it back**, as FlClash's popups do: a `GlassMenuSource` around the button
  (every `PopupMenuButton` through `GlassMenuPress`, and a pull-down's value) is snapshotted and hidden while its
  menu is open, and `GlassMenuMorph` draws the snapshot sinking into the card as it opens and coming back in the
  droplet as it returns, so the button shows again just where the droplet lands. Call `arm()` right before opening
  the menu; one opened another way, from the keyboard or for assistive technology, finds the source standing where it
  opens from. A pick that changes the button waits for `landed`, so the value changes in place.
- **Call sites with surfaces of their own** (popovers, banners, a framed screenshot) check `GlassSurfaces.installed`
  and draw on `GlassSurfaces.panel` or `GlassSurfaces.pill` instead. Controls that fill themselves, as `iconButton`
  does, ask `GlassSurfaces.onGlass(context)` and fill with `glassFillOf` there.
- **Pages opened from a glass button grow out of it**, as FlClash's popovers do: `GlassMorphButton` is a
  `LiquidGlassButton` whose `onTap` gets the button, and `button.toNamed(...)` opens a named route through
  `GetPageRoute` with the morph as its transition, returning into the button as a drop when it closes. The home
  header's search and messages buttons use it. It falls back to `Get.toNamed` with animations off. While it morphs
  the page is drawn from a snapshot taken as it starts to open or return, and keeps the keyboard insets it started
  with; a page holds back what would jank the morph, as the search page's keyboard, with
  `GlassMorphButton.deferUntilOpened`. The page under it, the button's, is drawn from a snapshot too, taken once the
  button has hid: the route keeps its overlay entry opaque while it morphs, so the navigator leaves that page, its
  own glass and all, unpainted rather than drawing it again every frame (Impeller keeps no raster cache). Only the
  top page, covering those under it, is taken; otherwise it paints as it is. A button on a pane it shares, as in a `GlassButtonGroup`, opens a page the
  same way through `GlassMorphSource`, whose `builder` gets the source to call `toNamed` on: only its face hides
  while the page is open, and the pane stays, unless it is its group's lone button, which hides the whole group as a
  `GlassMorphButton` hides. Off glass it is `Get.toNamed`. The two share the opening through a private mixin.
- **Buttons in a row share one pane**, as iOS 26's toolbars group theirs: `GlassButtonGroup` sets its `children`
  (`IconButton`s, `PopupMenuButton`s, `TextButton`s, kept as they are) side by side, or along `Axis.vertical`, on
  one capsule, a circle around a lone one. On it a button is 44 dp a side; a pressed one alone stands on a platter
  inset 2 dp, concentric with the pane, without a ripple; a focused one takes a ring; a disabled one keeps
  Material's grey; a `PopupMenuButton`'s menu grows out of its button. While every button hides the pane is not
  drawn. Off glass (`glass`, the switch when null) it is a plain `Flex` of the same buttons.
- **Switches are near iOS's size on glass.** The app shrinks every `Switch` with `Transform.scale`; a new one takes
  `scale: GlassSurfaces.switchScale`, which keeps Material's at 0.8 and the glass one at 0.9.

## Secondary pages' title bars

`GlassAppBar` (`glass_app_bar.dart`) is the title bar of a page pushed over another: 设置 and its pages, and the
favourites, history, messages, follows and other pages whose `SimpleScaffold` or `Scaffold` has an
`appBar: AppBar(...)` with a title, a way back and a few actions. With glass on it is iOS 26's navigation bar: the
back button a 44 dp circle of glass, the title centered, the actions together on one capsule of glass, all over
`LiquidGlassHeader`'s fade and laid over the content, which scrolls under it. With glass off it builds the very
`AppBar` it replaces, so the page is as before. A bar that is something else, as a search field for a title, a
collapsing `SliverAppBar` or a bar over the video, is not for it.

**Adopting it** takes two edits, as `lib/pages/setting/` shows:

1. Rename `AppBar(` to `GlassAppBar(` in `SimpleScaffold.appBar`. It takes `title`, `leading`,
   `automaticallyImplyLeading`, `actions` and `centerTitle` as `AppBar` does; a page that needs another adds it,
   passed on to `AppBar` too. Actions stay as they are, together in a `GlassButtonGroup` (a lone one on a circle):
   an `Obx` that hides its button shrinks it, and the childless `SizedBox` that spaces Material's actions from the
   edge is left out on glass. An action that opens a page wraps its button in a `GlassMorphSource` and calls
   `source.toNamed(...)` in place of `Get.toNamed`; alone, its circle opens as a `GlassMorphButton` does.
2. Make room at the top of the content, below.

`SimpleScaffold` sees an `OverlaidAppBar` and, with glass on, lays the body under it at full height through
`GlassAppBarBody`. A page that keeps a Material `Scaffold`, for snack bars or a drawer, does it by hand, as
`setting/pages/logs.dart`:

```dart
final appBar = GlassAppBar(title: const Text('日志'), actions: [...]);
return Scaffold(
  appBar: GlassAppBar.enabled ? null : appBar,
  body: GlassAppBarBody(appBar: appBar, body: body),
);
```

**Making room.** The body's `HeaderOverlayInset` is the status bar + 56 dp (+ 46 with tabs), and the status bar is
taken out of its `MediaQuery` padding; with glass off the inset is 0, so the room costs nothing there. It can only be
read below the scaffold: a page that builds its list in its own `build` holds a context above it, where
`HeaderOverlayInset.of(context)` is 0. So:

- a `ListView` or `Column` built there starts with `const HeaderOverlaySpace()`, a `CustomScrollView` with
  `const SliverHeaderOverlaySpace()`, and a `ReorderableListView` takes it as its `header`;
- `ListView.builder`, `.separated` or anything that needs the number reads it in a `Builder`, as `CommonSetting`;
- a widget with a build of its own (a tab's page, a list widget, a page shown without its bar beside another, as
  设置's landscape panes with `showAppBar: false`) reads `HeaderOverlayInset.of(context)` or `.sliver(context)` there;
  `refreshIndicator` already does;
- fixed content that would sit under the bar takes the space above it (`display_mode.dart`, the sliders in
  `fullscreen_sc.dart`); centered content, as an error, can stay;
- content with glass of its own, as the live home page previewed in `color_select.dart`, lies below the bar in
  `HeaderOverlayInset.below`, since glass never passes under glass.

A page split into panes on glass gives each its own `SimpleScaffold` and bar, as iPad's split views do (设置 in
landscape, `_buildGlassPanes`): each title stands over its own pane, the divider runs between the bars, and the
detail pane, shown with `showAppBar: false`, makes room for its pane's bar. With glass off it keeps its one
Material bar. The title stands on a soft patch of the surface of its own, since it reads on the fade, not on glass;
the buttons' glass sees the content as the home header's does.

**A search in the bar**, as 设置's: `expandTitle: true` makes the title a pane of its own, 44 dp tall, filling the row
8 dp from the back circle and the actions (14 dp from the sides, as the home header's rhythm). 设置 passes a
`GlassMorphButton` capsule with the hint 搜索设置 in place of its title, and drops the list's search row on glass; the
page it opens, 设置搜索, lays its field on a capsule in the same place, so the morph lands where it left, and holds
its keyboard back with `GlassMorphButton.deferUntilOpened` until it has opened. With glass off both pages keep their
Material bars.

**Pages with tabs** pass them as `tabs: LiquidGlassTabBar(controller: ..., labels: ..., onTap: ...)`: with glass on
they are a second row of glass under the title, and the inset covers them. With glass off the argument is ignored and
the page keeps its own `TabBar` in the body, which it leaves out on glass: `if (!GlassAppBar.enabled) TabBar(...)`.
Each tab's list makes room as above; the inset reaches through `TabBarView`. Something between the bar and the tabs,
as history's pause tip, moves below the bar on glass, in `HeaderOverlayInset.below`.

**Multi-select.** `MultiSelectAppBarWidget` swaps the page's bar for a selection bar. To bring it on glass, let it
take a `GlassAppBar` and build a `GlassAppBar` while selecting too (取消 as `leading`, on a circle; 全选 and 移除 as
`TextButton` actions, on one capsule; the page bar's `tabs`), and implement `OverlaidAppBar`, so that `SimpleScaffold`
lays it over the body. The two are as tall, so the content stays put as they swap.

## Files

| File | Role | Edit? |
| ---- | ---- | ----- |
| `liquid_glass.dart`, `liquid_glass_capture.dart` (part), `shaders/liquid_glass.frag` | Glass core, ported from FlClash (GPL-3.0) | Only with a `// PiliPlus:` comment on each change. Don't reformat |
| `liquid_glass_skia.dart` (part) | Without Impeller, shadows and rims drawn from images on the device's pixels | Yes |
| `goo.dart` | Two shapes flowing together as one outline, ported from FlClash's `lib/ui/goo.dart` (GPL-3.0) | Same as the core |
| `glass_support.dart` | The FlClash helpers the core imports (tone shift, motion, radii, shapes) | Yes |
| `glass_spring.dart` | `GlassSpring`, a retargetable spring that is a `ValueListenable<double>` | Yes |
| `glass_theme.dart` | `floatingGlassShadows`; `glassPlatterColor`, a neutral shade as iOS's tab bars have, the item's own color saying which is current | Yes |
| `liquid_glass_button.dart` | A pressable pane: swells and glows under the finger, keyboard focusable | Yes |
| `liquid_glass_tab_bar.dart` | Tabs on a glass pill, with a platter that slides with the pages | Yes |
| `liquid_glass_header.dart` | A header over a soft fade, for content that scrolls under it | Yes |
| `glass_app_bar.dart` | `GlassAppBar`, a secondary page's title bar, Material's `AppBar` with glass off; `GlassAppBarBody` lays it over a body; `HeaderOverlaySpace` and `SliverHeaderOverlaySpace` read the room for it where they are built | Yes |
| `glass_panel.dart` | `GlassPanel`: glass with a rim and a wide shadow, clipping its child, as a menu or alert | Yes |
| `glass_alert_actions.dart` | An alert's buttons as iOS lays them out: capsules, the last one filled, 取消 at the bottom | Yes |
| `glass_switch.dart` | `GlassSwitch`, iOS 26's switch (a 63×28 track, a white capsule thumb) with FlClash's motion: a press lifts the thumb into a lens over the track. A `Switch`'s own `thumbIcon` (a lock) stays on the thumb; the theme's tick doesn't | Yes |
| `glass_surfaces.dart` | Fills the material_ui hooks: alerts (34 dp, thicker glass, grow in, swell on press), menus (24 dp, rows inset 8), the selection toolbar and switches; `panel`, `pill`, `onGlass` for call sites | Yes |
| `video_glass.dart` | `VideoGlass`: a backdrop filter pane over the video, which the host cannot replay; the player's and live room's controls, notes and full-screen panels | Yes |
| `glass_droplet.dart` | The return into a button as a drop of glass, shared by menus and pages: where the platter and droplet stand at a time, their shadows | Yes |
| `glass_menu_morph.dart` | A menu growing out of its button's capsule into the card; a press slid on into it lights and picks a row; it returns into the button as a drop of glass. `GlassMenuSource`, the button it takes in and gives back | Yes |
| `glass_page_morph.dart` | `GlassMorphButton`: a page growing out of its button and returning into it, on the route's own time, drawn from a snapshot; `GlassMorphSource`, the same out of a button in a `GlassButtonGroup` | Yes |
| `glass_button_group.dart` | `GlassButtonGroup`: buttons side by side on one pane of glass, each pressed on a platter of its own | Yes |
| `glass_menu_press.dart` | `GlassMenuPress`: a `PopupMenuButton` opens on press and carries the press on into its menu | Yes |
| `glass_fab.dart` | `GlassFab` (and `.extended`), a page's floating action button: a drop of glass in the theme's color with the switch on, Material's `FloatingActionButton` with it off. It keeps Material's footprint, and room above for its shadow so a `SlideTransition` by its own height hides that too. Already on glass (`GlassSurfaces.onGlass`, or a `VideoGlass` panel over the video) it takes no pane, only a fill, as an alert's default action. `GlassFabGroup` stacks round ones, as the blacklist's: on one `GlassButtonGroup` pane down the page with the switch on, Material's a margin apart with it off | Yes |
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
  `HeaderOverlayInset.below(...)` when it pins headers of its own. A `ListView` takes `HeaderOverlayInset.of(context)`
  as its top padding, as the mine page's does. `RefreshIndicator` reads the inset, so the pull indicator comes out
  from under the header. A bar at the bottom that the keyboard moves, as a chat's input bar, lays out through
  `GlassChatLayout` (`lib/pages/whisper_detail/widget/glass_chat_layout.dart`), which hands the list under it the
  bar's height in the same frame, so the newest message moves with the bar.
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

Pages read `GlassAppBar.enabled` as they build, so a test sets `GlassAppBar.debugEnabled` in `setUp`, before it builds
the page, and clears it in `tearDown`: `test/common/widgets/liquid_glass/glass_app_bar_test.dart`.

`VideoGlass` is a backdrop filter, which `toImage()` renders headless without the host:
`test/common/widgets/liquid_glass/video_glass_render_test.dart` passes both with and without `--enable-impeller`.

Put throwaway render tests in a scratch folder rather than `test/`.
