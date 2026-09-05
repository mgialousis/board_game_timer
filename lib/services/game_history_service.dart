import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_record.dart';

/// Stores finished games so past results can be looked up later.
///
/// The whole log is one JSON array under one key, kept newest-first and capped
/// at [maxEntries] — shared_preferences holds its contents in memory, so the
/// log has to stay bounded. Entries are compact ([GameRecord] drops per-turn
/// history), which keeps the cap generous in practice.
class GameHistoryService {
  static const String _key = 'turntimer.history';

  /// Oldest games are evicted beyond this many.
  static const int maxEntries = 50;

  /// All archived games, newest first. Individually malformed entries are
  /// skipped rather than discarding the whole log.
  Future<List<GameRecord>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final records = <GameRecord>[];
      for (final entry in decoded) {
        try {
          records.add(GameRecord.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return _sorted(records);
    } catch (_) {
      await prefs.remove(_key);
      return [];
    }
  }

  /// Adds [record], or replaces the existing entry with the same id — so
  /// re-saving a game after editing its scores updates it in place instead of
  /// creating a duplicate.
  Future<void> save(GameRecord record) async {
    final records = await list();
    records.removeWhere((r) => r.id == record.id);
    records.add(record);
    await _write(_sorted(records));
  }

  Future<void> delete(String id) async {
    final records = await list();
    records.removeWhere((r) => r.id == id);
    await _write(records);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Newest first, then trimmed to the cap so the oldest games fall off.
  List<GameRecord> _sorted(List<GameRecord> records) {
    records.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    if (records.length > maxEntries) {
      return records.sublist(0, maxEntries);
    }
    return records;
  }

  Future<void> _write(List<GameRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final r in records) r.toJson()]),
    );
  }
}
