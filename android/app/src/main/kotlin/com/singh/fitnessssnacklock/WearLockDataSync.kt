package com.singh.fitnessssnacklock

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/**
 * Publishes the full saved-lock list to the Wear OS app at [DATA_PATH].
 * Credentials stay in [PairedLockSecureStorage]; names and pin order come from
 * the Flutter saved-lock list. [KEY_UPDATED_AT] changes on every publish so
 * DataClient still syncs when only a name or pin flag changed.
 */
object WearLockDataSync {
    private const val TAG = "WearLockDataSync"
    const val DATA_PATH = "/vigo_vault_keys"
    const val LEGACY_DATA_PATH = "/lock_config"
    const val KEY_LOCKS = "locks"
    const val KEY_UPDATED_AT = "updatedAt"

    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val FLUTTER_LOCKS_KEY = "flutter.smart_lock_saved_locks"
    private const val FLUTTER_LEGACY_ID_KEY = "flutter.smart_lock_last_device_id"
    private const val FLUTTER_LEGACY_NAME_KEY = "flutter.smart_lock_custom_device_name"
    private const val PLACEHOLDER_MAC = "FF:FF:FF:11:22:33"

    fun syncAllFromLocalStorage(context: Context) {
        val appContext = context.applicationContext
        val locks = try {
            readSavedLocks(appContext)
        } catch (error: Exception) {
            Log.e(TAG, "Failed to read saved locks for watch sync", error)
            return
        } ?: return

        publish(appContext, locks)
    }

    private fun readSavedLocks(context: Context): List<WatchLockPayload>? {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        if (prefs.contains(FLUTTER_LOCKS_KEY)) {
            val raw = prefs.getString(FLUTTER_LOCKS_KEY, null)?.trim().orEmpty()
            if (raw.isEmpty() || raw == "[]") return emptyList()
            val array = try {
                JSONArray(raw)
            } catch (error: Exception) {
                Log.e(TAG, "Saved lock list is not valid JSON; leaving the watch unchanged", error)
                return null
            }
            if (array.length() == 0) return emptyList()
            return payloadsFromArray(context, array)
        }

        val legacyId = prefs.getString(FLUTTER_LEGACY_ID_KEY, null)?.trim().orEmpty()
        if (legacyId.isEmpty()) return emptyList()
        val legacyName = prefs.getString(FLUTTER_LEGACY_NAME_KEY, null)
        val legacy = JSONArray().put(
            JSONObject()
                .put("id", legacyId)
                .put("displayName", legacyName ?: "Smart Lock")
                .put("isPinned", false),
        )
        return payloadsFromArray(context, legacy)
    }

    private fun payloadsFromArray(context: Context, array: JSONArray): List<WatchLockPayload> {
        val storage = PairedLockSecureStorage(context)
        val payloads = ArrayList<WatchLockPayload>(array.length())
        for (index in 0 until array.length()) {
            val obj = array.optJSONObject(index) ?: continue
            val mac = resolveMac(obj)
            val id = jsonString(obj, "id").ifBlank { mac }
            if (mac.isEmpty()) {
                Log.w(TAG, "Skipping saved lock $id — no hardware MAC for standalone watch unlock")
                continue
            }
            val advName = jsonString(obj, "hardwareName", "advName")
            val displayName = jsonString(obj, "displayName").ifBlank {
                advName.ifBlank { "Smart Lock" }
            }
            val batteryLevel = batteryLevelOf(obj)
            payloads.add(
                WatchLockPayload(
                    id = id,
                    displayName = displayName,
                    advName = advName,
                    mac = mac,
                    aesKey = credential(storage.getSecretKey(id), storage.getSecretKey(mac))
                        ?: LockProtocolDefaults.FACTORY_ENCRYPT_KEY,
                    password = credential(storage.getPassword(id), storage.getPassword(mac))
                        ?: LockProtocolDefaults.FACTORY_PASSWORD_HEX,
                    isPinned = obj.optBoolean("isPinned", false),
                    batteryLevel = batteryLevel,
                    batteryUpdatedAt = if (batteryLevel == null) {
                        0L
                    } else {
                        jsonEpoch(obj, "batteryReadAt").takeIf { it > 0L }
                            ?: jsonEpoch(obj, "lastConnectedAt")
                    },
                ),
            )
        }
        return sortPinnedFirst(payloads)
    }

    private fun publish(context: Context, locks: List<WatchLockPayload>) {
        val locksJson = JSONArray().apply {
            for (lock in locks) {
                put(
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
        }.toString()

        val request = PutDataMapRequest.create(DATA_PATH).apply {
            dataMap.putString(KEY_LOCKS, locksJson)
            dataMap.putLong(KEY_UPDATED_AT, System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        val client = Wearable.getDataClient(context)
        client.putDataItem(request)
            .addOnSuccessListener {
                Log.d(TAG, "Published ${locks.size} lock(s) to $DATA_PATH")
                client.deleteDataItems(Uri.parse("wear://*$LEGACY_DATA_PATH"))
                    .addOnFailureListener { error ->
                        Log.w(TAG, "Could not remove legacy $LEGACY_DATA_PATH item", error)
                    }
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed to publish lock list to watch", error)
            }
    }

    private fun credential(primary: String?, fallback: String?): String? {
        return primary?.trim().takeUnless { it.isNullOrEmpty() }
            ?: fallback?.trim().takeUnless { it.isNullOrEmpty() }
    }

    private fun resolveMac(obj: JSONObject): String {
        val explicit = normalizeMac(jsonString(obj, "hardwareMac", "mac", "macAddress"))
        if (explicit.isNotEmpty() && explicit != PLACEHOLDER_MAC) return explicit
        val fromId = normalizeMac(jsonString(obj, "id"))
        if (fromId.isNotEmpty() && fromId != PLACEHOLDER_MAC) return fromId
        return ""
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

    private fun batteryLevelOf(obj: JSONObject): Int? {
        val raw = when {
            obj.has("lastBatteryLevel") && !obj.isNull("lastBatteryLevel") ->
                obj.optInt("lastBatteryLevel", -1)
            obj.has("batteryLevel") && !obj.isNull("batteryLevel") ->
                obj.optInt("batteryLevel", -1)
            else -> -1
        }
        return raw.takeIf { it in 1..100 }
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

    private fun sortPinnedFirst(locks: List<WatchLockPayload>): List<WatchLockPayload> {
        val pinned = ArrayList<WatchLockPayload>()
        val unpinned = ArrayList<WatchLockPayload>()
        for (lock in locks) {
            if (lock.isPinned) pinned.add(lock) else unpinned.add(lock)
        }
        return pinned + unpinned
    }

    private data class WatchLockPayload(
        val id: String,
        val displayName: String,
        val advName: String,
        val mac: String,
        val aesKey: String,
        val password: String,
        val isPinned: Boolean,
        val batteryLevel: Int?,
        val batteryUpdatedAt: Long,
    )
}

object LockProtocolDefaults {
    const val FACTORY_ENCRYPT_KEY = "3A60432A5C01211F291E0F4E0C132825"
    const val FACTORY_PASSWORD_HEX = "303030303030"
}
