# Repository Guidelines

## Project Structure & Module Organization

This is a Flutter/Dart mobile app targeting Android and iOS. `lib/main.dart` owns bootstrap and lifecycle wiring. Domain data lives in `lib/models/`; pure state transitions belong in `lib/controllers/game_engine.dart`, while `game_controller.dart` coordinates persistence and platform side effects. UI is split across `lib/screens/`, `lib/widgets/`, and `lib/theme/`. Services wrap storage, audio, wake-lock, and locked-play integrations. Shared helpers are in `lib/utils/`.

Tests live in `test/` and generally mirror the production concern, for example `game_engine_test.dart`. Audio and launcher inputs are under `assets/`. Android-specific locked-play code is in `android/app/src/main/kotlin/.../board_game_timer/`; avoid editing generated Flutter registrant files in `android/` or `ios/`.

## Build, Test, and Development Commands

- `flutter pub get`: install dependencies from `pubspec.lock`.
- `flutter run`: launch on a connected device or emulator.
- `flutter analyze`: run `flutter_lints` static analysis.
- `dart format --set-exit-if-changed .`: verify Dart formatting without rewriting files.
- `flutter test`: run the full unit and widget suite.
- `flutter test test/game_engine_test.dart`: run one focused test file.
- `flutter build apk`: produce an Android release APK.

## Coding Style & Naming Conventions

Use Dart's standard two-space formatting and keep `flutter analyze` clean. Name files `lower_snake_case.dart`, types `UpperCamelCase`, and members `lowerCamelCase`. Prefer immutable models, `const` values/widgets, and small methods. Keep timing transitions deterministic and side-effect free in `GameEngine`; access plugins through services so controller tests remain isolated. Kotlin code follows standard four-space indentation and existing package naming.

## Testing Guidelines

Use `flutter_test`; name files `*_test.dart` and describe observable behavior in `test` or `testWidgets` names. Inject clocks and service fakes instead of waiting on real time or invoking plugins. Add regression coverage for timer math, pause/resume, undo, persistence, and lock-screen action reconciliation when those paths change. There is no configured coverage threshold; use `flutter test --coverage` for broader changes.

## Commit & Pull Request Guidelines

Git history is not included in this checkout, so no repository-specific message pattern can be verified. Use concise, imperative subjects such as `Fix paused-turn reconciliation`, and keep each commit focused. Pull requests should explain behavior changes, list verification commands, link relevant issues, and include screenshots or recordings for UI changes. Call out Android/iOS permission, notification, or lifecycle effects explicitly.
