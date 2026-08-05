package com.singh.fitnessssnacklock.wear.data

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class LockConfig(
    val macAddress: String,
    val secretKey: String,
)

class LockConfigRepository private constructor(
    context: Context,
) {
    private val appContext = context.applicationContext

    private val _lockConfig = MutableStateFlow<LockConfig?>(loadCachedConfig())
    val lockConfig: StateFlow<LockConfig?> = _lockConfig.asStateFlow()

    fun updateFromDataItem(dataItem: DataItem) {
        if (dataItem.uri.path != DATA_PATH) return
        val config = parseConfig(dataItem) ?: return
        persistConfig(config)
        _lockConfig.value = config
    }

    fun update(macAddress: String, secretKey: String) {
        val config = LockConfig(
            macAddress = macAddress,
            secretKey = secretKey.ifBlank { DEFAULT_SECRET_KEY },
        )
        persistConfig(config)
        _lockConfig.value = config
    }

    private fun parseConfig(dataItem: DataItem): LockConfig? {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val macAddress = dataMap.getString(KEY_MAC_ADDRESS)?.trim().orEmpty()
        if (macAddress.isEmpty()) return null

        val secretKey = dataMap.getString(KEY_SECRET_KEY)?.trim()
            .takeUnless { it.isNullOrEmpty() }
            ?: DEFAULT_SECRET_KEY

        return LockConfig(macAddress = macAddress, secretKey = secretKey)
    }

    private fun loadCachedConfig(): LockConfig? {
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val macAddress = prefs.getString(KEY_MAC_ADDRESS, null)?.trim().orEmpty()
        if (macAddress.isEmpty()) return null

        val secretKey = prefs.getString(KEY_SECRET_KEY, DEFAULT_SECRET_KEY) ?: DEFAULT_SECRET_KEY
        return LockConfig(macAddress = macAddress, secretKey = secretKey)
    }

    private fun persistConfig(config: LockConfig) {
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MAC_ADDRESS, config.macAddress)
            .putString(KEY_SECRET_KEY, config.secretKey)
            .apply()
    }

    companion object {
        const val DATA_PATH = "/lock_config"
        const val KEY_MAC_ADDRESS = "mac_address"
        const val KEY_SECRET_KEY = "secret_key"
        const val DEFAULT_SECRET_KEY = "3A60432A5C01211F291E0F4E0C132825"
        private const val PREFS_NAME = "wear_lock_config"

        val DATA_URI: Uri = Uri.parse("wear://*/$DATA_PATH")

        @Volatile
        private var instance: LockConfigRepository? = null

        fun getInstance(context: Context): LockConfigRepository {
            return instance ?: synchronized(this) {
                instance ?: LockConfigRepository(context).also { instance = it }
            }
        }
    }
}
