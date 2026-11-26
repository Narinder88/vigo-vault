package com.singh.fitnessssnacklock

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.singh.fitnessssnacklock/paired_locks"

    override fun onResume() {
        super.onResume()
        WearLockDataSync.syncAllFromLocalStorage(applicationContext)
    }

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

                    "getSecretKey" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(storage.getSecretKey(deviceId))
                    }

                    "saveSecretKey" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val secretKey = call.argument<String>("secretKey")
                        if (deviceId.isNullOrBlank() || secretKey.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId and secretKey are required", null)
                            return@setMethodCallHandler
                        }
                        storage.saveSecretKey(deviceId, secretKey)
                        result.success(null)
                    }

                    "removeSecretKey" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        storage.removeSecretKey(deviceId)
                        result.success(null)
                    }

                    "hasSecretKey" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(storage.hasSecretKey(deviceId))
                    }

                    "getPassword" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(storage.getPassword(deviceId))
                    }

                    "savePassword" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val password = call.argument<String>("password")
                        if (deviceId.isNullOrBlank() || password.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId and password are required", null)
                            return@setMethodCallHandler
                        }
                        storage.savePassword(deviceId, password)
                        result.success(null)
                    }

                    "removePassword" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        storage.removePassword(deviceId)
                        result.success(null)
                    }

                    "hasPassword" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_argument", "deviceId is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(storage.hasPassword(deviceId))
                    }

                    "syncLockToWatch", "syncAllLocksToWatch" -> {
                        WearLockDataSync.syncAllFromLocalStorage(applicationContext)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
