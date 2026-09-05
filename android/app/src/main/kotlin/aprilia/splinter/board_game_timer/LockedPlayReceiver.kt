package aprilia.splinter.board_game_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles taps on the "Locked play" notification buttons (which work on the
 * lock screen). It updates the on-device snapshot for an instant response and
 * records the action, then asks the running service to redraw the notification.
 */
class LockedPlayReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_NEXT = "aprilia.splinter.board_game_timer.NEXT"
        const val ACTION_PAUSE = "aprilia.splinter.board_game_timer.PAUSE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val now = System.currentTimeMillis()
        when (intent.action) {
            ACTION_NEXT -> LockedPlayStore.next(context, now)
            ACTION_PAUSE -> LockedPlayStore.togglePause(context, now)
            else -> return
        }
        // Redraw via the already-running foreground service.
        val update = Intent(context, LockedPlayService::class.java)
            .setAction(LockedPlayService.ACTION_UPDATE)
        try {
            context.startService(update)
        } catch (e: Exception) {
            // Service not foregroundable from here on some versions; the next
            // app resume will reconcile and refresh regardless.
        }
    }
}
