# TurnTimer — Board Game Timer

[![CI](https://github.com/mgialousis/board_game_timer/actions/workflows/ci.yml/badge.svg)](https://github.com/mgialousis/board_game_timer/actions/workflows/ci.yml)

TurnTimer is a Flutter app for tracking thinking time in tabletop games. The
active player's color fills the screen, one tap passes the turn, and the final
summary turns every move into useful per-player statistics.

It supports 2–8 players, optional score and dice-roll tracking, crash-safe local
persistence, game history, dark mode, and an Android lock-screen mode that keeps
long sessions usable with the display off. No account, backend, or network
connection is required.

## Engineering highlights

- A pure, deterministic game engine keeps timing, pause, undo, skip, and dice
  transitions independently testable.
- Timestamp-derived elapsed time stays accurate across lifecycle changes
  without a background timer.
- A native Android foreground service exposes next/pause actions on the lock
  screen, then reconciles them through the same Dart state engine.
- Defensive JSON persistence restores interrupted games and remains compatible
  with older saved data.
- 155 unit and widget tests cover the engine, controller, persistence,
  native-action reconciliation, statistics, and primary UI flows.

The implementation is intentionally dependency-light: `ChangeNotifier` for
state, `shared_preferences` for local storage, and small service adapters around
platform behavior. See [Architecture](#architecture) for the design rationale.

## What it does

1. **Setup** — pick 2–8 players, give each a name and color, optionally name the
   game, reorder players, and optionally randomize who goes first.
2. **Play** — the active player's color fills the screen with their name, a big
   live turn timer, their running total, and a preview of who's next.
   - **Tap anywhere** → end the current turn, start the next (circular order).
   - **Tap the "Next" pill** → hand the turn to any player instead, including
     the same player again (Catan's snake-order setup needs both).
   - **Long-press** (or the Pause button) → pause/resume. No one accrues time
     while paused.
   - **Undo** → revert the last turn change (or skip), keeping stats consistent.
   - **Skip** → the current player passes; their in-progress time is discarded.
   - **End game** → confirm, then see the summary.
3. **Scores** — when the game ends you're asked for each player's final score
   (optional, skippable, editable afterwards). Highest score wins; a tie shows
   as a draw.
4. **Summary** — the winner, then per player: score, total time, % of total,
   turn count, average turn, and longest turn, with the most-time and
   slowest-average players highlighted. Rematch with the same players, start a
   new game, or copy the results as text.
5. **Dice** (optional) — with *Track dice rolls* on, a strip of the numbers
   2–12 sits under the board. Tap the number that was just rolled: it logs the
   roll and passes the turn in the same tap. The distribution is charted at the
   end and kept in history. See below.
6. **History** — every finished game is archived automatically and listed under
   the ⏱ history button on the home screen: who won, when, how long, and the
   full per-player breakdown. Replay any past line-up with one tap. Delete a
   single game (with an Undo in the snackbar) or clear the whole log.

## How to run

```bash
flutter pub get
flutter run            # on a connected device or emulator/simulator

flutter test           # run the unit + widget tests
flutter analyze        # static analysis (clean)
```

Requirements: Flutter 3.38+ / Dart 3.10+ (developed against Flutter 3.38.8).
Targets Android and iOS.

## Main features

- Material 3 UI with full light/dark support (follows the system setting).
- Large, glanceable game screen designed to be read across a table.
- Active-player color background with a subtle, slow pulse animation.
- Full-screen tap target with accidental double-tap debouncing.
- Pause/resume, undo (multi-level), skip, end-game confirmation.
- Lightweight haptic feedback on turn changes and pause toggles.
- Crash/quit-safe: the active game is persisted and restored automatically.
- Battery saver mode (disables the pulse).
- Three screen modes for a game: **Normal**, **Keep screen awake**, and
  **Locked play (screen off)** — see below.
- Optional soft per-turn time-limit warning (Off / 1 / 2 / 3 / 5 min) with a
  one-time haptic **and a short chime** when a turn first runs long.
- **Final scores and a winner** — optional integer score per player (negatives
  allowed), highest wins, ties shown as a draw.
- **Dice roll tracking** — Catan-style 2d6 logging with a live histogram and an
  actual-vs-expected distribution chart on the results and history screens.
- **Pass the turn to any player** — for setup phases and out-of-order turns.
- **Game history** — past games archived locally with their times and scores.
- Copy the final summary to the clipboard.

## Dice roll tracking (Catan)

Turn on **⚙ → Track dice rolls**. A strip of the numbers 2–12 appears under the
board, and each button's fill shows how often that number has come up so far —
the input *is* the live histogram.

**One rule decides what a number tap does:** the roll belongs to the player
whose turn is *starting*.

- If the active player hasn't rolled yet, the tap logs their roll and the clock
  keeps running for them. (This is the first roll of the game.)
- If they already have one, the tap **passes the turn and logs the roll for the
  incoming player** — one tap per turn, the same as tapping to pass.

Which one is about to happen is written above the strip, so it is never a guess.

**Passing without a roll** is just the old gesture: tap the board anywhere. That
is what Catan's initial placement phase uses — those turns are timed, but no
dice are involved. The rule above then self-heals: the next number tapped
attaches to the player who is already up, so a missed roll never shifts the
attribution of everything after it.

- **Fixing a mistake** — tap the "*name* rolled *n*" chip to change or remove
  the current roll. **Undo** also drops a logged roll, and undoing a roll never
  rewinds the clock.
- **Skip** keeps a roll that was already logged: the dice were physically
  rolled, so the distribution should know.
- **Rolls can't be logged from the lock screen**, so Locked play and dice
  tracking don't combine. Nothing breaks if you use both — those turns simply
  have no roll.

At the end of the game (and in every history entry) the rolls are charted
against what a fair pair of dice would have produced, with per-player roll and
7 counts on each stat card.

## Locked play — advance turns from the lock screen (Android)

For long games, choose **⚙ → Screen during game → Locked play (screen off)**.
The phone's screen can then turn off completely; an ongoing notification takes
over as the "board display":

- It is **tinted with the active player's color** and shows their name.
- The turn time is rendered by the OS notification **chronometer**, so it ticks
  live without the app running or waking up every second.
- **Next** and **Pause/Resume** buttons work directly from the lock screen — no
  unlocking needed.
- When you reopen the app, every action taken from the lock screen is **replayed
  through the same game engine** used in-app (each tap is stored with its
  timestamp), so history, statistics, and the running turn are exactly as if you
  had tapped in the app.

**Why this is the most energy-efficient mode:** the display is by far the
biggest battery drain, and "keep screen awake" pays that cost for the whole
game. In Locked play the screen is off; what remains is a lightweight foreground
service whose notification the OS redraws — the app itself holds no timers and
does no per-second work. Timing accuracy is unaffected because elapsed time is
always derived from timestamps, never from a running counter.

On Android 13+ the app asks for the notification permission when you select
this mode. (iOS support — a Live Activity with App Intents — is a planned
future improvement.)

## Architecture

Deliberately small and flat — `ChangeNotifier`, no heavyweight state or codegen.

```
lib/
  main.dart                       # app bootstrap, theme, lifecycle wiring, routing
  models/
    player.dart                   # id, name, color + projected stats
    turn_record.dart              # one completed turn (active duration)
    undo_entry.dart               # one reversible step (relative elapsed)
    game_state.dart               # immutable live game state
    game_record.dart              # finished game: stats, scores, winner, dice
    app_settings.dart             # persisted preferences
    screen_mode.dart              # normal / keepAwake / lockedPlay
    dice_mode.dart                # off / 2d6
    dice_roll.dart                # one logged roll (player + total)
  controllers/
    game_engine.dart              # PURE state transitions (shared with lock screen)
    game_controller.dart          # side effects around the engine; ChangeNotifier
  services/
    game_storage_service.dart     # shared_preferences JSON persistence
    game_history_service.dart     # archived games (upsert by id, capped)
    screen_wake_service.dart      # wakelock_plus wrapper (swappable in tests)
    live_play_service.dart        # bridge to the lock-screen surface + action log
    warning_sound_service.dart    # turn-warning chime (audioplayers, fail-safe)
  screens/
    setup_screen.dart
    game_screen.dart              # tap/long-press, 1s ticker, pulse, lifecycle
    summary_screen.dart           # results + score entry/editing
    history_screen.dart           # past games, newest first
    history_detail_screen.dart    # one past game, replay its line-up
  widgets/
    timer_display.dart            # tabular-figures clock text
    stat_card.dart                # one player's summary row
    game_result_body.dart         # shared results layout + winner banner
    score_entry_sheet.dart        # final-score input
    dice_strip.dart               # in-game number pad / live histogram
    dice_distribution_chart.dart  # actual-vs-expected results chart
    player_color_picker.dart      # palette swatch picker
  theme/app_theme.dart            # Material 3 light/dark from one seed color
  utils/
    duration_format.dart          # formatClock / formatCompact (clamp negatives)
    date_format.dart              # history timestamps (no intl dependency)
    dice.dart                     # 2d6 probabilities + DiceStats aggregate
    palette.dart                  # player color palette + contrast helper

android/.../board_game_timer/
  MainActivity.kt                 # MethodChannel: start/update/stop/drainActions
  LockedPlayService.kt            # foreground service: colored chronometer notif
  LockedPlayReceiver.kt           # lock-screen button taps -> snapshot + action log
  LockedPlayStore.kt              # SharedPreferences snapshot + append-only actions
```

**State management — `ChangeNotifier`.** The app is small and has a single
source of truth (`GameController`). Riverpod/Bloc would be overkill. The
controller exposes derived getters and notifies listeners on each action; the
game screen also runs a 1-second UI ticker (see below).

**Persistence — `shared_preferences`.** There is only ever one active game, so
the whole `GameState` is serialized to a single JSON string under one key. No
database, schema, or migrations needed. Settings live under a second key so a
fresh game remembers your last choices. Loads are defensive: a corrupt or
invalid payload is discarded instead of crashing on launch.

**Finished games — `GameRecord`, not `GameState`.** The live model carries turn
history, an undo stack and pause bookkeeping that a finished game has no use
for, so ending a game projects it into a compact `GameRecord` (per-player
aggregates + scores). That record is what the results screen and the history
log both render — via the shared `GameResultBody` widget — and what gets
archived, which keeps each history entry a few hundred bytes regardless of how
many turns were played. Dice follow the same principle: the live game holds
`DiceRoll` objects, while the archive stores two flat int lists (totals and the
index of who rolled each), which is a few hundred bytes for a whole game and
still enough to rebuild the distribution *and* its per-player breakdown.

**Backwards compatibility.** Every field added after 1.0 is read with a default
(`rolls ?? []`, `diceMode ?? off`, `currentTurnRolled ?? false`), and the UI for
each is gated on whether the data exists (`hasRolls`, `hasScores`). A game saved
by an older build restores and plays normally, an older history entry renders
exactly as it always did, and no migration step ever runs. Its id is derived from the game's own timestamps, so
re-saving after a score edit updates the existing entry instead of duplicating
it. History lives under its own key, newest first, capped at 50 games.

**Keep awake — `wakelock_plus`,** funneled through `ScreenWakeService` so the
controller never imports the plugin directly (keeps it unit-testable and
degrades gracefully where the plugin is unavailable).

**Locked play — pure engine + action replay.** All state transitions live in
`GameEngine` (pure functions of `GameState` + a timestamp). The Android side
never mutates real game state: notification taps update a small display
snapshot (for instant lock-screen response) and append `{action, timestamp}` to
a log. On resume, `GameController` drains the log and replays each action
through `GameEngine` at its recorded timestamp — deterministic, so the
authoritative state matches what the lock screen showed to the second. If the
notification permission is denied, everything degrades gracefully to normal
in-app play.

### Timer design (accurate + battery-friendly)

Time is **never** counted by a running counter that depends on every tick.
Instead the state stores timestamps and elapsed time is *derived*:

```
elapsed(now) = clampNonNegative( (isPaused ? pausedAt : now) - currentTurnStartTime )
```

- **Pause** records `pausedAt`; **resume** shifts `currentTurnStartTime` forward
  by the paused gap, so elapsed continues seamlessly and `endTime - startTime`
  always equals the recorded active `duration`.
- Because elapsed is computed from `DateTime.now()`, it stays correct through
  lag, and through the app being backgrounded — no catch-up logic, no negative
  durations.
- **Undo** stores the *relative* elapsed to restore (not an absolute timestamp),
  so it is correct no matter how much time passed before you pressed Undo, and
  it respects the current pause state.
- Per-player stats (`accumulatedDuration`, `turnCount`, `longestTurn`) are a
  **projection of the turn history**, recomputed after every change, so undo and
  skip can never leave them inconsistent.

## Battery-friendly design decisions

- **One redraw per second, scoped.** A single `Timer.periodic(1s)` bumps a
  `ValueNotifier`; only the timer text widgets listen to it, so the rest of the
  tree is not rebuilt every second. The display updates once per second, not per
  frame.
- **No background timers.** The ticker and pulse are stopped when the app is
  backgrounded, when paused, and when the game ends. On resume, elapsed is
  recomputed from timestamps — accuracy comes from the clock, not from a timer
  that ran in the background.
- **Subtle, gated animation.** The pulse is a slow (~2.8s) ≤3% scale breath. It
  runs only while the game is actively running, foregrounded, and battery saver
  is off.
- **Battery saver mode** disables the pulse entirely (the once-per-second clock
  still updates, which is negligible).
- **The turn warning costs nothing extra** — it is derived from the existing
  once-per-second tick (no additional timer), so it works even in battery saver
  mode.
- **Locked play lets the screen turn off entirely** — the biggest possible
  saving. The OS renders the ticking chronometer in the notification; the app
  process does no per-second work while the phone is locked.
- **Dark-mode friendly** Material 3 theming.
- **Stable digits.** The big timer uses tabular figures so seconds don't trigger
  per-tick relayout/width jitter.

## Edge cases handled

Covered by unit tests in `test/`:

- Multiple pause/resume cycles — no time accrues while paused.
- Undo after one or more turns; undo of a skip; undo while paused.
- End game while running or while paused (finalizes the in-progress turn; no
  phantom zero-length turn is recorded).
- App backgrounded/resumed (simulated via clock jumps) stays accurate.
- No negative durations even if the device clock moves backwards.
- At least 2 players required; player names cannot be empty.
- Stats remain consistent after undo.
- Discarding an active game requires confirmation.

## Testing

- `test/duration_format_test.dart` — formatting incl. negative clamping.
- `test/game_state_test.dart` — JSON round-trip, summary getters, and the
  legacy-settings migration to `ScreenMode`.
- `test/game_engine_test.dart` — the pure transitions in isolation, including
  every dice rule (log vs. pass, attribution to the incoming player, undo
  dropping a roll without rewinding the clock, skip, corrections) and
  `passTurnTo` (any player, the same player again, undo).
- `test/dice_test.dart` — the 2d6 probability table (sums to 36, symmetric),
  expected counts, and the `DiceStats` aggregate incl. corrupt-entry tolerance.
- `test/game_record_test.dart` — finished-game statistics, ranking, and the
  winner rules (highest wins, ties, zero vs. unscored, negatives, partial
  scoring), the dice projection, that editing scores cannot erase the roll log,
  plus JSON round-trip and loading a pre-dice entry.
- `test/game_history_service_test.dart` — archive ordering, upsert-not-duplicate,
  the entry cap, delete/clear, and corrupt-entry tolerance.
- `test/game_controller_test.dart` — the timer/stat rules: timing accuracy,
  pause/resume, undo/skip, end-game finalization, persistence, rematch.
- `test/reconciliation_test.dart` — lock-screen actions replayed on
  resume/cold-start (timestamp-accurate durations, trailing pause, persistence)
  and the surface lifecycle (start/update/stop, permission request).
- `test/widget_test.dart` — setup renders, tap advances the player, turn
  warning appears, summary lists players, entering scores shows the winner and
  updates history, history list and empty state, the dice strip (hidden when
  off, logging vs. passing, correcting a roll, the distribution chart) and the
  "pass turn to…" picker.

The controller takes an injected clock (and storage/wake services), so all
timing logic is tested deterministically without real waits.

## Future improvements

- iOS Locked play via a Live Activity + App Intents (lock-screen buttons need
  iOS 17+; requires a native widget-extension target).
- In-game access to settings (toggle modes mid-game).
- Richer sound/haptics options.
- Share summary via the system share sheet (currently copies to clipboard).
- Cross-game aggregates (win counts, head-to-head records, an all-time roll
  distribution) on top of history.
- Logging both dice separately (spots a physically biased die) and support for
  the Cities & Knights event die.
- A "lowest score wins" option for golf-style games.
- Manual time adjustment for a player (correct mistakes).
- Localization.
