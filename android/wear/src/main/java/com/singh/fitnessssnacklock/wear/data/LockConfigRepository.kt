package com.singh.fitnessssnacklock.wear.data

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

data class SyncedLock(
    val id: String,
    val displayName: String,
    val advName: String,
    val mac: String,
    val aesKey: String,
    val password: String,
    val isPinned: Boolean,
    val batteryLevel: Int? = null,
    val batteryUpdatedAt: Long = 0L,
)

class LockConfigRepository private constructor(
    context: Context,
) {
    private val appContext = context.applicationContext
    private var hasMultiLockPayload = prefs().getBoolean(KEY_MULTI_PROTOCOL, false)
    private var lastUpdatedAt = prefs().getLong(KEY_UPDATED_AT, 0L)

    private val _locks = MutableStateFlow(loadCachedLocks())
    val locks: StateFlow<List<SyncedLock>> = _locks.asStateFlow()

    fun updateFromDataItem(dataItem: DataItem) {
        when (dataItem.uri.path) {
            DATA_PATH -> applyMultiLockPayload(dataItem)
            LEGACY_DATA_PATH -> applyLegacyPayload(dataItem)
        }
    }

    fun clear() {
        hasMultiLockPayload = true
        replaceLocks(emptyList(), updatedAt = System.currentTimeMillis(), multiProtocol = true)
    }

    private fun applyMultiLockPayload(dataItem: DataItem) {
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        val updatedAt = dataMap.getLong(KEY_UPDATED_AT, 0L)
        if (updatedAt > 0L && updatedAt < lastUpdatedAt) {
            Log.d(TAG, "Ignoring stale lock list updatedAt=$updatedAt < $lastUpdatedAt")
            return
        }
        val locks = parseLocksPayload(dataMap) ?: return
        hasMultiLockPayload = true
        replaceLocks(locks, updatedAt = updatedAt, multiProtocol = true)
    }

    private fun applyLegacyPayload(dataItem: DataItem) {
        if (hasMultiLockPayload) return
        val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
        if (dataMap.containsKey(KEY_LOCKS)) {
            applyMultiLockPayload(dataItem)
            return
        }
        val lock = parseLegacyLock(dataMap) ?: return
        replaceLocks(listOf(lock), updatedAt = 0L, multiProtocol = false)
    }

    fun updateBattery(lockId: String, mac: String, level: Int) {
        if (level !in 1..100) return
        val now = System.currentTimeMillis()
        synchronized(this) {
            val updated = _locks.value.map { lock ->
                if (sameLock(lock, lockId, mac)) {
                    lock.copy(batteryLevel = level, batteryUpdatedAt = now)
                } else {
                    lock
                }
            }
            persist(updated, multiProtocol = hasMultiLockPayload)
            _locks.value = updated
        }
        Log.d(TAG, "Stored battery $level% for $mac")
    }

    private fun replaceLocks(
        locks: List<SyncedLock>,
        updatedAt: Long,
        multiProtocol: Boolean,
    ) {
        synchronized(this) {
            val sorted = sortPinnedFirst(mergeBattery(locks))
            if (updatedAt > lastUpdatedAt) {
                lastUpdatedAt = updatedAt
            }
            persist(sorted, multiProtocol = multiProtocol)
            _locks.value = sorted
            Log.d(TAG, "Stored ${sorted.size} lock(s) for standalone unlock")
        }
    }

    private fun mergeBattery(incoming: List<SyncedLock>): List<SyncedLock> {
        val current = _locks.value
        return incoming.map { next ->
            val existing = current.firstOrNull { sameLock(it, next.id, next.mac) }
            val level = chooseBattery(existing, next)
            val batteryUpdatedAt = when {
                level == null -> 0L
                existing != null && level == existing.batteryLevel &&
                    existing.batteryUpdatedAt >= next.batteryUpdatedAt -> existing.batteryUpdatedAt
                else -> next.batteryUpdatedAt
            }
            next.copy(batteryLevel = level, batteryUpdatedAt = batteryUpdatedAt)
        }
    }

    private fun chooseBattery(existing: SyncedLock?, incoming: SyncedLock): Int? {
        val incomingLevel = incoming.batteryLevel
        val stored = existing ?: return incomingLevel
        val localLevel = stored.batteryLevel ?: return incomingLevel
        if (incomingLevel == null) return localLevel
        if (stored.batteryUpdatedAt > incoming.batteryUpdatedAt) return localLevel
        return incomingLevel
    }

    private fun sameLock(lock: SyncedLock, id: String, mac: String): Boolean {
        if (id.isNotBlank() && lock.id == id) return true
        return mac.isNotBlank() && lock.mac.equals(mac, ignoreCase = true)
    }

    private fun parseLocksPayload(dataMap: DataMap): List<SyncedLock>? {
        if (!dataMap.containsKey(KEY_LOCKS)) return null
        val raw = dataMap.getString(KEY_LOCKS)?.trim().orEmpty()
        if (raw.isEmpty() || raw == "[]") return emptyList()
        return parseLocksJson(raw)
    }

    private fun parseLocksJson(raw: String): List<SyncedLock>? {
        val array = try {
            JSONArray(raw)
        } catch (error: Exception) {
            Log.e(TAG, "Invalid locks JSON; keeping the current watch list", error)
            return null
        }
        val locks = ArrayList<SyncedLock>(array.length())
        for (index in 0 until array.length()) {
            val obj = array.optJSONObject(index) ?: continue
            parseLock(obj)?.let { locks.add(it) }
        }
        return locks
    }

    private fun parseLock(obj: JSONObject): SyncedLock? {
        val mac = resolveMac(obj)
        if (mac.isEmpty()) return null
        val advName = jsonString(obj, "advName", "hardwareName")
        val displayName = jsonString(obj, "displayName", "name").ifBlank {
            advName.ifBlank { "Smart Lock" }
        }
        return SyncedLock(
            id = jsonString(obj, "id").ifBlank { mac },
            displayName = displayName,
            advName = advName,
            mac = mac,
            aesKey = jsonString(obj, "aesKey", "secret_key", "secretKey")
                .ifBlank { DEFAULT_SECRET_KEY },
            password = jsonString(obj, "password", "passwordHex")
                .ifBlank { DEFAULT_PASSWORD_HEX },
            isPinned = obj.optBoolean("isPinned", false),
            batteryLevel = batteryLevelOf(obj),
            batteryUpdatedAt = batteryUpdatedAtOf(obj),
        )
    }

    private fun parseLegacyLock(dataMap: DataMap): SyncedLock? {
        val mac = normalizeMac(dataMap.getString(KEY_MAC_ADDRESS).orEmpty())
        if (mac.isEmpty() || mac == PLACEHOLDER_MAC) return null
        val secretKey = dataMap.getString(KEY_SECRET_KEY)?.trim()
            .takeUnless { it.isNullOrEmpty() }
            ?: DEFAULT_SECRET_KEY
        val password = dataMap.getString(KEY_PASSWORD)?.trim()
            .takeUnless { it.isNullOrEmpty() }
            ?: DEFAULT_PASSWORD_HEX
        return SyncedLock(
            id = mac,
            displayName = "Smart Lock",
            advName = "",
            mac = mac,
            aesKey = secretKey,
            password = password,
            isPinned = false,
        )
    }

    private fun loadCachedLocks(): List<SyncedLock> {
        val preferences = prefs()
        if (preferences.contains(KEY_LOCKS_JSON)) {
            val raw = preferences.getString(KEY_LOCKS_JSON, "[]").orEmpty()
            if (raw.isBlank() || raw == "[]") return emptyList()
            return sortPinnedFirst(parseLocksJson(raw) ?: emptyList())
        }
        val mac = preferences.getString(KEY_MAC_ADDRESS, null)?.trim().orEmpty()
        val normalized = normalizeMac(mac)
        if (normalized.isEmpty()) return emptyList()
        return listOf(
            SyncedLock(
                id = normalized,
                displayName = "Smart Lock",
                advName = "",
                mac = normalized,
                aesKey = preferences.getString(KEY_SECRET_KEY, DEFAULT_SECRET_KEY)
                    ?: DEFAULT_SECRET_KEY,
                password = preferences.getString(KEY_PASSWORD, DEFAULT_PASSWORD_HEX)
                    ?: DEFAULT_PASSWORD_HEX,
                isPinned = false,
            ),
        )
    }

    private fun persist(locks: List<SyncedLock>, multiProtocol: Boolean) {
        prefs().edit()
            .putString(KEY_LOCKS_JSON, locksToJson(locks))
            .putBoolean(KEY_MULTI_PROTOCOL, multiProtocol || hasMultiLockPayload)
            .putLong(KEY_UPDATED_AT, lastUpdatedAt)
            .remove(KEY_MAC_ADDRESS)
            .remove(KEY_SECRET_KEY)
            .remove(KEY_PASSWORD)
            .apply()
    }

    private fun locksToJson(locks: List<SyncedLock>): String {
        val array = JSONArray()
        for (lock in locks) {
            array.put(
                JSONObject()
                    .put("id", lock.id)
                    .put("displayName", lock.displayName)
                    .put("advName", lock.advName)
                    .put("mac", lock.mac)
                    .put("aesKey", lock.aesKey)
                    .put("password", lock.password)
                    .put("isPinned", lock.isPinned)
                    .put("batteryLevel", lock.batteryLevel ?: JSONObject.NULL)
                    .put("batteryUpdatedAt", lock.batteryUpdatedAt),
            )
        }
        return array.toString()
    }

    private fun prefs() = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val TAG = "WearLockConfig"
        const val DATA_PATH = "/vigo_vault_keys"
        const val LEGACY_DATA_PATH = "/lock_config"
        const val KEY_LOCKS = "locks"
        const val KEY_UPDATED_AT = "updatedAt"
        const val KEY_MAC_ADDRESS = "mac_address"
        const val KEY_SECRET_KEY = "secret_key"
        const val KEY_PASSWORD = "password"
        const val DEFAULT_SECRET_KEY = "3A60432A5C01211F291E0F4E0C132825"
        const val DEFAULT_PASSWORD_HEX = "303030303030"
        private const val KEY_LOCKS_JSON = "locks_json"
        private const val KEY_MULTI_PROTOCOL = "multi_lock_protocol"
        private const val PLACEHOLDER_MAC = "FF:FF:FF:11:22:33"
        private const val PREFS_NAME = "wear_lock_config"

        val DATA_URI: Uri = Uri.parse("wear://*$DATA_PATH")

        @Volatile
        private var instance: LockConfigRepository? = null

        fun getInstance(context: Context): LockConfigRepository {
            return instance ?: synchronized(this) {
                instance ?: LockConfigRepository(context).also { instance = it }
            }
        }

        private fun sortPinnedFirst(locks: List<SyncedLock>): List<SyncedLock> {
            val pinned = ArrayList<SyncedLock>()
            val unpinned = ArrayList<SyncedLock>()
            for (lock in locks) {
                if (lock.isPinned) pinned.add(lock) else unpinned.add(lock)
            }
            return pinned + unpinned
        }

        private fun resolveMac(obj: JSONObject): String {
            val explicit = normalizeMac(jsonString(obj, "mac", "hardwareMac", "mac_address", "macAddress"))
            if (explicit.isNotEmpty() && explicit != PLACEHOLDER_MAC) return explicit
            val fromId = normalizeMac(jsonString(obj, "id"))
            if (fromId.isNotEmpty() && fromId != PLACEHOLDER_MAC) return fromId
            return ""
        }

        private fun batteryLevelOf(obj: JSONObject): Int? {
            if (!obj.has("batteryLevel") || obj.isNull("batteryLevel")) {
                if (!obj.has("lastBatteryLevel") || obj.isNull("lastBatteryLevel")) return null
                return obj.optInt("lastBatteryLevel", -1).takeIf { it in 1..100 }
            }
            return obj.optInt("batteryLevel", -1).takeIf { it in 1..100 }
        }

        private fun batteryUpdatedAtOf(obj: JSONObject): Long {
            val direct = jsonEpoch(obj, "batteryUpdatedAt")
            if (direct > 0L) return direct
            return jsonEpoch(obj, "batteryReadAt")
        }

        private fun jsonEpoch(obj: JSONObject, key: String): Long {
            if (!obj.has(key) || obj.isNull(key)) return 0L
            val numeric = obj.optLong(key, 0L)
            if (numeric > 0L) return numeric
            val text = obj.optString(key, "").trim()
            if (text.isEmpty() || text == "null") return 0L
            return try {
                Instant.parse(text).toEpochMilli()
            } catch (_: Exception) {
                0L
            }
        }

        private fun jsonString(obj: JSONObject, vararg keys: String): String {
            for (key in keys) {
                if (!obj.has(key) || obj.isNull(key)) continue
                val value = obj.optString(key, "").trim()
                if (value.isNotEmpty() && value != "null") return value
            }
            return ""
        }

        private fun normalizeMac(raw: String): String {
            val compact = raw.trim().replace(":", "").replace("-", "").replace(" ", "")
            if (compact.length != 12 || compact.any { char ->
                    char !in '0'..'9' && char !in 'a'..'f' && char !in 'A'..'F'
                }
            ) {
                return ""
            }
            return compact.uppercase().chunked(2).joinToString(":")
        }
    }
}
