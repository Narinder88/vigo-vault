package com.singh.fitnessssnacklock.wear.data

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

class LockDataListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val repository = LockConfigRepository.getInstance(this)
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED) {
                repository.updateFromDataItem(event.dataItem)
            }
        }
    }
}
