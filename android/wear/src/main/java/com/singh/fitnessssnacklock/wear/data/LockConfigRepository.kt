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
    val passwordHex: String = LockConfigRepository.DEFAULT_PASSWORD_HEX,
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

    fun update(macAddress: String, secretKey: String, passwordHex: String = DEFAULT_PASSWORD_HEX) {
        val config = LockConfig(
            macAddress = macAddress,
            secretKey = secretKey.ifBlank { DEFAULT_SECRET_KEY },
            passwordHex = passwordHex.ifBlank { DEFAULT_PASSWORD_HEX },
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
        val passwordHex = dataMap.getString(KEY_PASSWORD)?.trim()
            .takeUnless { it.isNullOrEmpty() }
            ?: DEFAULT_PASSWORD_HEX

        return LockConfig(
            macAddress = macAddress,
            secretKey = secretKey,
            passwordHex = passwordHex,
        )
    }

    private fun loadCachedConfig(): LockConfig? {
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val macAddress = prefs.getString(KEY_MAC_ADDRESS, null)?.trim().orEmpty()
        if (macAddress.isEmpty()) return null

        val secretKey = prefs.getString(KEY_SECRET_KEY, DEFAULT_SECRET_KEY) ?: DEFAULT_SECRET_KEY
        val passwordHex = prefs.getString(KEY_PASSWORD, DEFAULT_PASSWORD_HEX) ?: DEFAULT_PASSWORD_HEX
        return LockConfig(
            macAddress = macAddress,
            secretKey = secretKey,
            passwordHex = passwordHex,
        )
    }

    private fun persistConfig(config: LockConfig) {
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_MAC_ADDRESS, config.macAddress)
            .putString(KEY_SECRET_KEY, config.secretKey)
            .putString(KEY_PASSWORD, config.passwordHex)
            .apply()
    }

    companion object {
        const val DATA_PATH = "/lock_config"
        const val KEY_MAC_ADDRESS = "mac_address"
        const val KEY_SECRET_KEY = "secret_key"
        const val KEY_PASSWORD = "password"
        const val DEFAULT_SECRET_KEY = "3A60432A5C01211F291E0F4E0C132825"
        const val DEFAULT_PASSWORD_HEX = "303030303030"
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
