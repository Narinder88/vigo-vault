package com.singh.fitnessssnacklock.wear.data

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

class LockConfigSync(
    private val context: Context,
) {
    private val dataClient by lazy { Wearable.getDataClient(context) }

    suspend fun refreshFromDataLayer() {
        val items = dataClient.dataItems.await()
        try {
            for (item in items) {
                if (item.uri.path == LockConfigRepository.DATA_PATH) {
                    LockConfigRepository.getInstance(context).updateFromDataItem(item)
                    return
                }
            }
        } finally {
            items.release()
        }
    }
}
