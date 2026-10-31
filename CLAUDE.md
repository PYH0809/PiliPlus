# PiliPlus

A third-party Bilibili client in Flutter for Android, iOS, Windows, macOS and Linux. This repository is a fork of
[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus); keep changes easy to send upstream or to rebase
onto it.

## Commands

```bash
flutter pub get
pwsh lib/scripts/patch.ps1 <android|ios|windows|macos|linux>
                         # Patches the Flutter SDK ($FLUTTER_ROOT) and material_ui in the pub cache, in place.
                         #   CI runs it before every build; the app relies on the patched APIs. Run it once per SDK.
flutter analyze          # Must stay at 0 errors and 0 warnings. Infos exist on main; don't add new ones
dart format <files>      # Only the files you changed. Never run it over ported or generated code (see below)
flutter test             # Unit and widget tests under test/
flutter test --enable-impeller <file>
                         # Needed for anything drawing with shaders, such as liquid glass
flutter run              # Debug run on the current platform
```

Linux hosts need `libgtk-3-dev libx11-dev libxi-dev` before `flutter test` can build native assets.

Release builds come from the manual **Build** workflow (`.github/workflows/build.yml`), not from local machines.
Its `android_dev` input builds the dev flavor (`--android-project-arg dev=1`): it installs as
`com.example.piliplus.dev`, "PiliPlus dev", next to the release app, and turns Impeller on, which release Android
builds keep off. The APK's build number (versionCode) is the commit count, so a phone refuses a build from a branch
with fewer commits than the one installed; the `build_number` input sets it by hand.

## Hard constraints

1. **Import with `package:PiliPlus/...`**, never relative paths (`always_use_package_imports`).
2. **Widgets import `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`.** The app runs on
   the `material_ui` package, which `patch.ps1` patches. Only SDK code copied under `lib/common/widgets/flutter/`
   keeps the SDK's own imports.
3. **Leave generated code alone**: `lib/grpc/bilibili/**` (protobuf) and `*.g.dart`.
4. **Keep copied and ported code close to its source**, so it can be synced again:
   - `lib/common/widgets/flutter/**` is adapted from the Flutter SDK;
   - `lib/common/widgets/liquid_glass/liquid_glass.dart`, `liquid_glass_capture.dart` and
     `shaders/liquid_glass.frag` are ported from [FlClash](https://github.com/chen08209/FlClash) (GPL-3.0).

   Don't reformat them, and mark each local change with a `// PiliPlus:` comment.
5. **Clean up what you start.** Dispose controllers, `AnimationController`s, `FocusNode`s, `ValueNotifier`s and stream
   subscriptions; check `mounted` before using `context` after an `await`.
6. **Network calls return `LoadingState<T>`** (`Success` / `Error`, `lib/http/loading_state.dart`) instead of throwing,
   and go through the per-domain `XxxHttp` classes in `lib/http/` on top of `Request` (`lib/http/init.dart`).
7. **Read settings through `Pref`**, never from a Hive box in a widget (see Settings below).
8. **Never commit signing material**: `*.jks`, `key.properties`. Both are gitignored; keys live in Actions secrets.
9. **Pin third-party GitHub Actions to a full commit SHA**, with the release in a comment:
   `uses: owner/repo@<40-char sha> # v1.2.3`. Secrets in this public repository depend on it.

## Architecture

| Path | What lives there |
| ---- | ---------------- |
| `lib/main.dart` | Startup: storage, services, theming, the app `builder` (wraps the app in liquid glass when it is on) |
| `lib/router/app_pages.dart` | GetX routes (`GetPage`); pages navigate with `Get.toNamed` |
| `lib/pages/<page>/` | One feature each: `view.dart` (widget), `controller.dart` (GetX controller), `widgets/` |
| `lib/pages/common/` | Base controllers: `CommonListController` (paged lists), `CommonDataController`, mixins |
| `lib/http/` | Dio client (`init.dart`), endpoints (`api.dart`), per-domain request classes, `LoadingState` |
| `lib/grpc/` | gRPC requests; `bilibili/` is generated protobuf |
| `lib/models/`, `lib/models_new/` | Response models. New models go in `models_new/`: plain classes with a hand-written `fromJson` |
| `lib/common/widgets/` | Shared widgets. `flutter/` holds adapted SDK widgets; `liquid_glass/` the glass module |
| `lib/utils/` | Storage (`storage.dart`, `storage_key.dart`, `storage_pref.dart`), extensions, platform helpers |
| `lib/services/`, `lib/plugin/` | Audio service, downloads, accounts; the player (`plugin/pl_player`) |
| `lib/scripts/` | SDK patches (`*.patch`), `patch.ps1`, CI build scripts |

**Pages and state.** Views are `StatefulWidget`s that `Get.put` their controller; controllers extend
`GetxController` or a base from `lib/pages/common/`, expose `Rx` values, and fetch in `onInit`. A list page usually
only overrides `customGetData()` on `CommonListController`.

**Settings.** A setting is three pieces: a key in `SettingBoxKey` (`lib/utils/storage_key.dart`), a typed getter with
its default in `Pref` (`lib/utils/storage_pref.dart`), and an entry (`SwitchModel` and friends) in
`lib/pages/setting/models/*_settings.dart`. Give the entry `needReboot: true` when the value is only read at startup.

**UI copy** is Chinese, written inline; there is no localization layer.

**Rendering.** Impeller is off in release Android builds (manifest placeholder `enableImpeller`, on only in the dev
flavor) and on macOS. Anything that needs shader filters must check `ImageFilter.isShaderFilterSupported` and fall
back, as liquid glass does.

**Style.** The formatter keeps trailing commas (`trailing_commas: preserve`). Dot shorthands (`.fromLTRB(...)`,
`type: .emote`) are used throughout; use them where the context type is clear.

Module notes: `lib/common/widgets/liquid_glass/CLAUDE.md`.

## Git and PR conventions

- **Commits and PR titles in English**, `type(scope): summary` (`feat`, `fix`, `opt`, `refactor`, `chore`, `ci`,
  `docs`). Upstream also takes short lowercase subjects such as `opt ui`.
- **PR descriptions in Chinese**, following `.github/pull_request_template.md`. Every PR that changes what users see
  carries screenshots and a `## ✅ 测试` checklist written from the user's side: each item unchecked, marked 🟢
  (covered by a test) or ⚪ (needs a manual try), with the platform and Impeller state it was checked under.
- **One topic per PR.** If a reviewer could accept one part and reject another, split it.
- Open PRs as drafts. Before pushing, run `flutter analyze` and the tests for what you touched.

## CI

| Workflow | Runs on | Notes |
| -------- | ------- | ----- |
| `check.yml` | Every PR and push to main | `flutter analyze` (0 errors, 0 warnings), `flutter test`, the glass tests again with `--enable-impeller`, and a release dev APK built with the debug key, which compiles `android/` and runs R8. Needs no secrets |
| `build.yml` | manual | Platforms are inputs; Android signs with the `SIGN_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and `KEY_PASSWORD` secrets, then checks each APK with `apksigner` and logs its SHA-256 |
| `ai_review.yml` | The owner's PRs out of draft, each push; anyone's PR by hand, with a PR number and a model | Codex reviews in Chinese through OpenRouter (`OPENROUTER_API_KEY`); the `AI_REVIEW_MODEL` variable picks the model. The footer gives the tokens and an estimated cost. Never blocks merging |

Fork PRs get no secrets, so a review on one skips.
