package com.singh.fitnessssnacklock.wear.data

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.WearableListenerService

class LockDataListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val repository = LockConfigRepository.getInstance(this)
        val changed = ArrayList<DataItem>()
        var currentPathDeleted = false
        for (event in dataEvents) {
            val path = event.dataItem.uri.path
            if (path != LockConfigRepository.DATA_PATH &&
                path != LockConfigRepository.LEGACY_DATA_PATH
            ) {
                continue
            }
            if (event.type == DataEvent.TYPE_DELETED && path == LockConfigRepository.DATA_PATH) {
                currentPathDeleted = true
            } else if (event.type == DataEvent.TYPE_CHANGED) {
                changed.add(event.dataItem)
            }
        }

        val current = changed.lastOrNull { it.uri.path == LockConfigRepository.DATA_PATH }
        if (current != null) {
            repository.updateFromDataItem(current)
            return
        }
        if (currentPathDeleted) {
            repository.clear()
            return
        }
        val legacy = changed.lastOrNull { it.uri.path == LockConfigRepository.LEGACY_DATA_PATH }
        if (legacy != null) {
            repository.updateFromDataItem(legacy)
        }
    }
}
