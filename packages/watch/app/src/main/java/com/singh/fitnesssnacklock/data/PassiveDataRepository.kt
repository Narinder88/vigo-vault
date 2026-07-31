/*
 * Copyright 2022 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.singh.fitnesssnacklock.data

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "passive_data")

class PassiveDataRepository(private val context: Context) {
    private val dataStore = context.dataStore;

    val passiveDataEnabled: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[PASSIVE_DATA_ENABLED] ?: false
    }

    suspend fun setPassiveDataEnabled(enabled: Boolean) {
        dataStore.edit { prefs ->
            prefs[PASSIVE_DATA_ENABLED] = enabled
        }
    }

    fun latestSteps(): Flow<Double> {
//        return dataStore.data.map { prefs ->
//            prefs[getLatestStepsKey(LocalDate.now())] ?: 0.0
//        }

        return dataStore.data.map { prefs ->
            prefs[doublePreferencesKey("STEPS")] ?: 0.0
        }
    }

    suspend fun storeLatestSteps(data: Double, date: LocalDate) {
//        dataStore.edit { prefs ->
//            prefs[getLatestStepsKey(date)] = data
//        }

        setLastDataSync();
        dataStore.edit { prefs ->
            prefs[doublePreferencesKey("STEPS")] = data
        }
    }

    fun latestCalories(): Flow<Double> {
//        return dataStore.data.map { prefs ->
//            prefs[getLatestCaloriesKey(LocalDate.now())] ?: 0.0
//        }

        return dataStore.data.map { prefs ->
            prefs[doublePreferencesKey("CALORIES")] ?: 0.0
        }
    }

    fun latestExerciseCalories(): Flow<Double> {
        return dataStore.data.map { prefs ->
            prefs[doublePreferencesKey("EXERCISE_CALORIES")] ?: 0.0
        }
    }

//    fun combineDailyCalories(): Flow<Double> {
//        return dataStore.data.map { prefs ->
//            (prefs[doublePreferencesKey("CALORIES")]
//                ?: 0.0) + (prefs[doublePreferencesKey("EXERCISE_CALORIES")] ?: 0.0)
//        }
//    }

    suspend fun storeLatestCalories(data: Double, date: LocalDate) {
//        dataStore.edit { prefs ->
//            prefs[getLatestCaloriesKey(date)] = data
//        }

        setLastDataSync();
        dataStore.edit { prefs ->
            prefs[doublePreferencesKey("CALORIES")] = data
        }
    }

    suspend fun storeLatestExerciseCalories(data: Double, date: LocalDate) {
        setLastDataSync();
        dataStore.edit { prefs ->
            prefs[doublePreferencesKey("EXERCISE_CALORIES")] = data
        }
    }

    private suspend fun setLastDataSync() {
        dataStore.edit { prefs ->
            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val dateFormated = LocalDate.now().format(formatter);
            Log.d("#### SYNC", dateFormated)
            prefs[LAST_DATA_SYNC] = dateFormated;
        }
    }

    val lastDataSync: Flow<String?> = dataStore.data.map { prefs ->
        prefs[LAST_DATA_SYNC]
    }

    companion object {
        private val PASSIVE_DATA_ENABLED = booleanPreferencesKey("passive_data_enabled")
        private val LAST_DATA_SYNC = stringPreferencesKey("last_data_sync")
        private fun getLatestStepsKey(date: LocalDate): Preferences.Key<Double> {
            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val dateFormated = date.format(formatter);
            val storedKey = "LATEST_STEPS_${dateFormated}";
            return doublePreferencesKey(storedKey);
        }

        private fun getLatestCaloriesKey(date: LocalDate): Preferences.Key<Double> {
            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val dateFormated = date.format(formatter);
            val storedKey = "LATEST_CALORIES_${dateFormated}";
            return doublePreferencesKey(storedKey);
        }
    }
}
