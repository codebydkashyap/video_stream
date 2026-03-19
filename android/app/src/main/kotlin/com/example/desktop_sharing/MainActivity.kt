package com.example.desktop_sharing

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.desktop_sharing/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        val title = call.argument<String>("title") ?: "Screen Sharing"
                        val body = call.argument<String>("body") ?: "You are sharing your screen..."
                        val mode = call.argument<String>("mode") ?: "initial"
                        val intent = Intent(this, com.cloudwebrtc.webrtc.FlutterForegroundService::class.java)
                        intent.putExtra("title", title)
                        intent.putExtra("body", body)
                        intent.putExtra("mode", mode)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        val intent = Intent(this, com.cloudwebrtc.webrtc.FlutterForegroundService::class.java)
                        stopService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
