package aprilia.splinter.board_game_timer

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Shared storage for the lock-screen surface: the current display snapshot and
 * an append-only log of the actions the user triggered from the notification.
 *
 * The service / receiver mutate the snapshot for instant on-device response and
 * append actions; Flutter drains the actions on resume and replays them through
 * the (authoritative) Dart GameEngine. Mirrors the iOS App-Group design.
 */
object LockedPlayStore {
    private const val PREFS = "turntimer_locked_play"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_ACTIONS = "actions"

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveSnapshot(ctx: Context, json: String) {
        prefs(ctx).edit().putString(KEY_SNAPSHOT, json).apply()
    }

    fun snapshot(ctx: Context): JSONObject? {
        val s = prefs(ctx).getString(KEY_SNAPSHOT, null) ?: return null
        return try {
            JSONObject(s)
        } catch (e: Exception) {
            null
        }
    }

    fun clear(ctx: Context) {
        prefs(ctx).edit().remove(KEY_SNAPSHOT).remove(KEY_ACTIONS).apply()
    }

    /** Returns the action-log JSON array string and clears it. */
    fun drainActions(ctx: Context): String {
        val actions = prefs(ctx).getString(KEY_ACTIONS, "[]") ?: "[]"
        prefs(ctx).edit().remove(KEY_ACTIONS).apply()
        return actions
    }

    private fun appendAction(ctx: Context, type: String, ts: Long) {
        val arr = try {
            JSONArray(prefs(ctx).getString(KEY_ACTIONS, "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        arr.put(JSONObject().put("type", type).put("timestampMillis", ts))
        prefs(ctx).edit().putString(KEY_ACTIONS, arr.toString()).apply()
    }

    /** Advances to the next player for immediate display + records the action. */
    fun next(ctx: Context, now: Long) {
        val snap = snapshot(ctx) ?: return
        val players = snap.optJSONArray("players") ?: return
        val n = players.length()
        if (n == 0) return
        val paused = snap.optBoolean("isPaused", false)
        snap.put("currentIndex", (snap.optInt("currentIndex", 0) + 1) % n)
        // GameEngine.nextTurn preserves the pause state. Mirror that behavior
        // so the notification and authoritative replay cannot diverge.
        snap.put(
            "turnStartMillis",
            if (paused) snap.optLong("pausedAtMillis", now) else now
        )
        saveSnapshot(ctx, snap.toString())
        appendAction(ctx, "next", now)
    }

    /** Toggles pause/resume for immediate display + records the action. */
    fun togglePause(ctx: Context, now: Long) {
        val snap = snapshot(ctx) ?: return
        if (snap.optBoolean("isPaused", false)) {
            // Resume: shift the start forward by the paused gap.
            val pausedAt = snap.optLong("pausedAtMillis", now)
            val start = snap.optLong("turnStartMillis", now)
            val gap = (now - pausedAt).coerceAtLeast(0L)
            snap.put("turnStartMillis", start + gap)
            snap.put("isPaused", false)
            snap.put("pausedAtMillis", 0L)
            saveSnapshot(ctx, snap.toString())
            appendAction(ctx, "resume", now)
        } else {
            snap.put("isPaused", true)
            snap.put("pausedAtMillis", now)
            saveSnapshot(ctx, snap.toString())
            appendAction(ctx, "pause", now)
        }
    }
}
