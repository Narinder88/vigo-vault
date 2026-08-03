package com.singh.fitnessssnacklock

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.singh.fitnessssnacklock/paired_locks"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val storage = PairedLockSecureStorage(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPaired" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(storage.isPaired(deviceId))
                    }

                    "pair" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        storage.pair(deviceId)
                        result.success(null)
                    }

                    "unpair" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        storage.unpair(deviceId)
                        result.success(null)
                    }

                    "getPairedIds" -> {
                        result.success(storage.getPairedIds().toList())
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
