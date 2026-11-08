package com.alphatech.financas

import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fin/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(
                        NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName))
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "drain" -> synchronized(BankNotificationService::class.java) {
                        val p = getSharedPreferences("fin_queue", MODE_PRIVATE)
                        val s = p.getString("q", "[]")
                        p.edit().putString("q", "[]").apply()
                        result.success(s)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
