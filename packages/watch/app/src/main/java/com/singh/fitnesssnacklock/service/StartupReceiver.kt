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
package com.singh.fitnesssnacklock.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.singh.fitnesssnacklock.PERMISSION
import com.singh.fitnesssnacklock.TAG
import com.singh.fitnesssnacklock.data.HealthServicesRepository
import com.singh.fitnesssnacklock.data.PassiveDataRepository
import com.singh.fitnesssnacklock.service.PassiveDataService.Companion.sendDataToPhone
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.logging.SimpleFormatter
import kotlin.random.Random
import kotlin.time.Duration.Companion.hours

/**
 * Background data subscriptions are not persisted across device restarts. This receiver checks if
 * we enabled background data and, if so, registers again.
 */
class StartupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val repository = PassiveDataRepository(context)


        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        runBlocking {
            if (repository.passiveDataEnabled.first()) {
                // Make sure we have permission.
                val result = context.checkSelfPermission(PERMISSION)
                if (result == PackageManager.PERMISSION_GRANTED) {
                    scheduleWorker(context)
                } else {
                    // We may have lost the permission somehow. Mark that background data is
                    // disabled so the state is consistent the next time the user opens the app UI.
                    repository.setPassiveDataEnabled(false)
                }
            }
        }
    }

    private fun scheduleWorker(context: Context) {
        // BroadcastReceiver's onReceive must complete within 10 seconds. During device startup,
        // sometimes the call to register for background data takes longer than that and our
        // BroadcastReceiver gets destroyed before it completes. Instead we schedule a WorkManager
        // job to perform the registration.
        Log.i(TAG, "Enqueuing worker")
        WorkManager.getInstance(context).enqueue(
            OneTimeWorkRequestBuilder<RegisterForBackgroundDataWorker>().build()
        )
    }

    private fun scheduleIntervalWorker(context: Context) {
        // BroadcastReceiver's onReceive must complete within 10 seconds. During device startup,
        // sometimes the call to register for background data takes longer than that and our
        // BroadcastReceiver gets destroyed before it completes. Instead we schedule a WorkManager
        // job to perform the registration.
        Log.i(TAG, "Interval worker")
        WorkManager.getInstance(context).enqueue(
            PeriodicWorkRequestBuilder<RegisterForIntervalWorker>(1, TimeUnit.MINUTES).build()
        )
    }
}

class RegisterForBackgroundDataWorker(
    private val appContext: Context,
    workerParams: WorkerParameters
) :
    CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        Log.i(TAG, "Worker running")
        val healthServicesRepository = HealthServicesRepository(appContext)
        healthServicesRepository.registerForHealthsData()
        return Result.success()
    }
}


fun scheduleIntervalWorker(context: Context) {
    // BroadcastReceiver's onReceive must complete within 10 seconds. During device startup,
    // sometimes the call to register for background data takes longer than that and our
    // BroadcastReceiver gets destroyed before it completes. Instead we schedule a WorkManager
    // job to perform the registration.
    Log.i(TAG, "#### Interval worker")

    val minute = Calendar.getInstance().get(Calendar.MINUTE);
    val minuteRemaining = 15 - minute % 15;
    Log.d(TAG, "#### REMAIN $minuteRemaining")
    WorkManager.getInstance(context).enqueueUniquePeriodicWork(
        "FSL_RESET_WORKER",
        ExistingPeriodicWorkPolicy.UPDATE,
        PeriodicWorkRequestBuilder<RegisterForIntervalWorker>(15, TimeUnit.MINUTES).setInitialDelay(
            minuteRemaining.toLong(),
            TimeUnit.MINUTES
        ).build(),
    )
}

class RegisterForIntervalWorker(private val appContext: Context, workerParams: WorkerParameters) :
    CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        Log.i(TAG, "#### INTERVAL running");
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        val minute = Calendar.getInstance().get(Calendar.MINUTE);

        if (hour == 0 && (minute in 0..16)) {
            Log.i(TAG, "#### INTERVAL RESET");

            val passiveDataRepository = PassiveDataRepository(appContext);
            val lastDataSyncStrNew = passiveDataRepository.lastDataSync.first();
            Log.d("#### LAST SYNC NEW", "$lastDataSyncStrNew");

            val formatterNew = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val currentFormatedNew = LocalDate.now().format(formatterNew);
//            if (lastDataSyncStrNew != null && lastDataSyncStrNew < currentFormatedNew) {
            val currentFormatter = SimpleDateFormat("dd-MM-yyyy HH:mm", Locale.getDefault())
            Log.d("#### RS NEW", currentFormatter.format(Date()));
            passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
            passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
            passiveDataRepository.storeLatestExerciseCalories(0.0, LocalDate.now())

            appContext.sendDataToPhone("STEPS", 0.0)
            appContext.sendDataToPhone("CALORIES", 0.0)
//            }
        }

        return Result.success()
    }
}
