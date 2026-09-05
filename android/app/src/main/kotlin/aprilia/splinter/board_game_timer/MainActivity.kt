package aprilia.splinter.board_game_timer

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "turntimer/locked_play"
    private val notificationPermissionRequest = 9911
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        (call.arguments as? String)?.let {
                            LockedPlayStore.saveSnapshot(applicationContext, it)
                            startLockedService(LockedPlayService.ACTION_START)
                        }
                        result.success(null)
                    }
                    "update" -> {
                        (call.arguments as? String)?.let {
                            LockedPlayStore.saveSnapshot(applicationContext, it)
                            startLockedService(LockedPlayService.ACTION_UPDATE)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        startLockedService(LockedPlayService.ACTION_STOP)
                        LockedPlayStore.clear(applicationContext)
                        result.success(null)
                    }
                    "drainActions" ->
                        result.success(LockedPlayStore.drainActions(applicationContext))
                    "requestPermissions" -> {
                        requestNotificationPermission(result)
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startLockedService(action: String) {
        val intent = Intent(this, LockedPlayService::class.java).setAction(action)
        try {
            if (action == LockedPlayService.ACTION_START &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            // Best effort; the in-app UI remains the source of truth.
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (NotificationManagerCompat.from(this).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    this, Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED)
        ) {
            result.success(true)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotificationResult?.success(false)
            pendingNotificationResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequest
            )
        } else {
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequest) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED &&
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        pendingNotificationResult?.success(granted)
        pendingNotificationResult = null
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        startActivity(intent)
    }
}
