package com.singh.fitnessssnacklock

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

object WearLockDataSync {
    private const val TAG = "WearLockDataSync"
    const val DATA_PATH = "/lock_config"
    const val KEY_MAC_ADDRESS = "mac_address"
    const val KEY_SECRET_KEY = "secret_key"

    fun syncLockToWatch(
        context: Context,
        macAddress: String,
        secretKey: String?,
    ) {
        val normalizedMac = macAddress.trim()
        if (normalizedMac.isEmpty()) {
            Log.w(TAG, "Skipping sync — mac_address is empty")
            return
        }

        val resolvedSecret = secretKey?.trim().takeUnless { it.isNullOrEmpty() }
            ?: LockProtocolDefaults.FACTORY_ENCRYPT_KEY

        val request = PutDataMapRequest.create(DATA_PATH).apply {
            dataMap.putString(KEY_MAC_ADDRESS, normalizedMac)
            dataMap.putString(KEY_SECRET_KEY, resolvedSecret)
            dataMap.putLong("timestamp", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(context.applicationContext)
            .putDataItem(request)
            .addOnSuccessListener {
                Log.d(TAG, "Synced lock config to watch for $normalizedMac")
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed to sync lock config to watch", error)
            }
    }

    fun syncFromStorage(context: Context, deviceId: String) {
        val storage = PairedLockSecureStorage(context.applicationContext)
        val secretKey = storage.getSecretKey(deviceId)
        syncLockToWatch(
            context = context,
            macAddress = deviceId,
            secretKey = secretKey,
        )
    }

    fun syncFirstPairedLock(context: Context) {
        val storage = PairedLockSecureStorage(context.applicationContext)
        val deviceId = storage.getPairedIds().firstOrNull() ?: run {
            Log.d(TAG, "No paired locks to sync to watch")
            return
        }
        syncFromStorage(context, deviceId)
    }
}

object LockProtocolDefaults {
    const val FACTORY_ENCRYPT_KEY = "3A60432A5C01211F291E0F4E0C132825"
}
