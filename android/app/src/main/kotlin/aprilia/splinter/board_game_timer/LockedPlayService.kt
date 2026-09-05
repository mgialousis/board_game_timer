package aprilia.splinter.board_game_timer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that renders the lock-screen "Locked play" surface: an
 * ongoing notification tinted with the active player's color, an OS-rendered
 * chronometer (so nothing wakes per second), and Next / Pause action buttons.
 */
class LockedPlayService : Service() {
    companion object {
        // Keep the version in the ID: Android does not let apps raise the
        // importance of an existing channel after it has been created.
        const val CHANNEL_ID = "turntimer_locked_play_v2"
        const val NOTIF_ID = 4711
        const val ACTION_START = "aprilia.splinter.board_game_timer.START"
        const val ACTION_UPDATE = "aprilia.splinter.board_game_timer.UPDATE"
        const val ACTION_STOP = "aprilia.splinter.board_game_timer.STOP"
        private const val GREY = 0xFF888888.toInt()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        createChannel()
        val snap = LockedPlayStore.snapshot(this)
        val players = snap?.optJSONArray("players")

        var name = "Player"
        var color = GREY
        if (players != null && players.length() > 0) {
            val index = (snap.optInt("currentIndex", 0)).coerceIn(0, players.length() - 1)
            players.optJSONObject(index)?.let {
                name = it.optString("name", "Player")
                color = it.optInt("color", GREY)
            }
        }
        val gameName = snap?.optString("gameName", "") ?: ""
        val paused = snap?.optBoolean("isPaused", false) ?: false
        val turnStart = snap?.optLong("turnStartMillis", System.currentTimeMillis())
            ?: System.currentTimeMillis()

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_turn)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentTitle(name)
            .setContentText(
                if (paused) "Paused"
                else if (gameName.isNotEmpty()) gameName
                else "Tap Next when the turn ends"
            )
            .setColor(color)
            .setColorized(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(turnStart)
            .setUsesChronometer(!paused)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .addAction(
                R.drawable.ic_stat_turn,
                "Next",
                actionIntent(LockedPlayReceiver.ACTION_NEXT, 1)
            )
            .addAction(
                R.drawable.ic_stat_turn,
                if (paused) "Resume" else "Pause",
                actionIntent(LockedPlayReceiver.ACTION_PAUSE, 2)
            )

        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }
        return builder.build()
    }

    private fun actionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, LockedPlayReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Locked play controls",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Turn timer controls shown while the phone is locked"
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }
}
