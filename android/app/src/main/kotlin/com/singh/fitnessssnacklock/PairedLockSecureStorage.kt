package com.singh.fitnessssnacklock

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

class PairedLockSecureStorage(context: Context) {
    private val prefs = EncryptedSharedPreferences.create(
        PREFS_FILE_NAME,
        MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC),
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun getPairedIds(): Set<String> {
        return prefs.getStringSet(PAIRED_IDS_KEY, emptySet())?.toSet() ?: emptySet()
    }

    fun isPaired(deviceId: String): Boolean {
        return getPairedIds().contains(deviceId)
    }

    fun pair(deviceId: String) {
        val updated = getPairedIds().toMutableSet()
        updated.add(deviceId)
        prefs.edit().putStringSet(PAIRED_IDS_KEY, updated).apply()
    }

    fun unpair(deviceId: String) {
        val updated = getPairedIds().toMutableSet()
        updated.remove(deviceId)
        prefs.edit().putStringSet(PAIRED_IDS_KEY, updated).apply()
    }

    companion object {
        private const val PREFS_FILE_NAME = "vigo_vault_paired_locks"
        private const val PAIRED_IDS_KEY = "paired_lock_ids"
    }
}
