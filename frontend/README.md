# QuietPass, Flutter foundation

Step 1 of the build: the project skeleton with the approved Teal dual-mode
theme wired in. Running this shows the foundation (both modes, real status
colours, chips, badges, primary action) before any product screens exist.

## What is here

```
lib/
  main.dart                         entry point, wraps app in ProviderScope
  app.dart                          MaterialApp, ScreenUtil, both themes, ThemeMode
  theme/
    app_palette.dart                raw hex values, dark + light (single source)
    app_colors.dart                 semantic tokens as a ThemeExtension + status resolver
    app_theme.dart                  ThemeData builders, Plus Jakarta type scale
    dimens.dart                     spacing (4pt) and radius scale
    theme_x.dart                    context.colors / context.text shortcuts
  features/
    theme/theme_controller.dart     Riverpod ThemeMode (defaults to system)
    home/foundation_preview_page.dart  temporary preview screen (replaced later)
```

## Rules the whole app follows

- No widget hardcodes a hex. Read colours from `context.colors` (semantic
  tokens), never from `app_palette.dart` directly.
- No widget hardcodes a raw pixel. Use `Space.*` and `Radii.*` with the
  screenutil extensions (`.w`, `.h`, `.r`), scaled from the 375x812 reference.
- Never put a fixed height on anything holding text; let it size to content so
  large system fonts do not clip. This is the responsiveness guardrail.
- One status enum (`HouseStatus`) is the source of truth; colours for the
  active mode come from `context.colors.statusOf(status)`.

## Setup and run

Requires Flutter 3.22+ (Dart 3.4+).

```
cd quietpass_app
flutter create .            # generates android/ios/etc platform folders
flutter pub get
flutter run
```

`flutter create .` fills in the platform folders around this lib/. It will not
overwrite the files already here. Tap the sun/moon button in the top right to
switch modes, or change your device theme to see it follow the system.

## Next steps

1. Group and status data model (entities, membership, roles, TTL statuses).
2. Backend skeleton: FastAPI, Postgres, Redis, on managed hosting.
3. Auth: phone OTP.
