import 'package:wakelock_plus/wakelock_plus.dart';

/// Thin wrapper around `wakelock_plus`.
///
/// Funneling the plugin through one class keeps the controller free of plugin
/// imports (so it stays unit-testable — tests inject a no-op subclass) and lets
/// us degrade gracefully on platforms where the plugin is unavailable.
class ScreenWakeService {
  bool _enabled = false;

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    try {
      await WakelockPlus.toggle(enable: value);
    } catch (_) {
      // Plugin missing / unsupported platform — safe to ignore.
    }
  }
}
