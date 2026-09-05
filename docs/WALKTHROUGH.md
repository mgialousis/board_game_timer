# TurnTimer: two-minute walkthrough

[Back to overview](../README.md)

1. **Setup:** choose at least two players and edit their names and colors.
   The preview uses fictional players Alex and Sam. Optionally name the game.
2. **Play:** start the game. The active player's color and clock fill the
   screen. Tap the board to pass a turn; long-press or tap Pause to pause.
3. **Optional dice:** enable Track dice rolls in Settings before starting.
   The first number records the current player's roll; after that player's
   roll is recorded, the next number passes and records the incoming roll.
4. **Finish:** tap End, confirm, and enter scores or choose Skip. The results
   show per-player thinking time and, when enabled, the dice distribution.
5. **History:** return home and open History to revisit the completed session.

<p>
  <img src="screenshots/01-setup.png" width="240" alt="Two-player setup" />
  <img src="screenshots/02-playing.png" width="240" alt="Active timer and optional dice strip" />
  <img src="screenshots/03-results.png" width="240" alt="Results and dice distribution" />
</p>

## Reproduce these captures

Run the app on an Android emulator using `flutter run --release`, use synthetic
player names, and follow the steps above. Capture settled screens with the
emulator's screenshot button. These September 2026 captures use dark mode;
they are actual app screens, not design mockups. Timing/statistics reflect a
short demonstration, not representative gameplay or a dice-fairness study.

Avoid capturing real player history, notifications, or signing configuration.
Native lock-screen behavior needs a separate physical-device check; these
screenshots do not demonstrate it.
