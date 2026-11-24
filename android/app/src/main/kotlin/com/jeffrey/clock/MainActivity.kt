package com.jeffrey.clock

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val METHOD_CHANNEL = "com.jeffrey.clock/mic"
        const val EVENT_CHANNEL = "com.jeffrey.clock/mic_status"
        const val PERMISSION_REQUEST = 7001
    }

    private var pendingStart: Triple<String, Int, MethodChannel.Result>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val host = call.argument<String>("host")
                    val port = call.argument<Int>("port")
                    if (host.isNullOrEmpty() || port == null) {
                        result.success(false)
                    } else {
                        requestStart(host, port, result)
                    }
                }
                "stop" -> {
                    MicService.stop(this)
                    result.success(null)
                }
                "status" -> result.success(MicService.status)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    MicService.listener = { events.success(it) }
                    events.success(MicService.status)
                }

                override fun onCancel(arguments: Any?) {
                    MicService.listener = null
                }
            },
        )
    }

    private fun requiredPermissions(): List<String> {
        val list = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            list.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        return list
    }

    private fun requestStart(host: String, port: Int, result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            MicService.start(this, host, port)
            result.success(true)
            return
        }
        pendingStart?.third?.success(false)
        pendingStart = Triple(host, port, result)
        requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val pending = pendingStart ?: return
        pendingStart = null
        val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) MicService.start(this, pending.first, pending.second)
        pending.third.success(granted)
    }
}
