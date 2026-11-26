package com.singh.fitnessssnacklock.wear.data

import android.content.Context
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

class LockConfigSync(
    private val context: Context,
) {
    private val dataClient by lazy { Wearable.getDataClient(context) }

    suspend fun refreshFromDataLayer() {
        val items = dataClient.dataItems.await()
        try {
            var current: DataItem? = null
            var legacy: DataItem? = null
            for (item in items) {
                when (item.uri.path) {
                    LockConfigRepository.DATA_PATH -> current = item
                    LockConfigRepository.LEGACY_DATA_PATH -> legacy = item
                }
            }
            val repository = LockConfigRepository.getInstance(context)
            when {
                current != null -> repository.updateFromDataItem(current)
                legacy != null -> repository.updateFromDataItem(legacy)
            }
        } finally {
            items.release()
        }
    }
}
