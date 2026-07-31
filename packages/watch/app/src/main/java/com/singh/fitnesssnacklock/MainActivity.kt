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
package com.singh.fitnesssnacklock

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.singh.fitnesssnacklock.presentation.PassiveDataApp
import com.singh.fitnesssnacklock.service.PassiveDataService.Companion.sendDataToPhone
import com.singh.fitnesssnacklock.service.scheduleIntervalWorker
import dev.inmo.krontab.EveryMinuteScheduler
import dev.inmo.krontab.doWhileTz
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.newSingleThreadContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar

class MainActivity : ComponentActivity() {
    @OptIn(ExperimentalCoroutinesApi::class, DelicateCoroutinesApi::class)
    private val scope = CoroutineScope(newSingleThreadContext("name"))
    private val context = this;

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val healthServicesRepository = (application as MainApplication).healthServicesRepository
        val passiveDataRepository = (application as MainApplication).passiveDataRepository

        scope.launch {
            scheduleIntervalWorker(context);
            val lastDataSyncStr = passiveDataRepository.lastDataSync.first();
            Log.d("#### LAST SYNC", "$lastDataSyncStr");

            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val currentFormated = LocalDate.now().format(formatter);
            if (lastDataSyncStr != null && lastDataSyncStr < currentFormated) {
                Log.d("#### MANUAL RESET", "$lastDataSyncStr");
                passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
                passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
                passiveDataRepository.storeLatestExerciseCalories(0.0, LocalDate.now())

                context.sendDataToPhone("STEPS", 0.0)
                context.sendDataToPhone("CALORIES", 0.0)
            }

            EveryMinuteScheduler.doWhileTz {
                Log.e("#### ST", passiveDataRepository.latestSteps().first().toString());
                Log.e("#### CL", passiveDataRepository.latestCalories().first().toString());
                Log.e(
                    "#### ECL",
                    passiveDataRepository.latestExerciseCalories().first().toString()
                );


                val formatter1 = DateTimeFormatter.ofPattern("yyyy-MM-dd")
                val currentFormated1 = LocalDate.now().format(formatter1);
                if (lastDataSyncStr != null && lastDataSyncStr < currentFormated1) {
                    Log.d("#### MANUAL RESET", "$lastDataSyncStr");
                    passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
                    passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
                    passiveDataRepository.storeLatestExerciseCalories(0.0, LocalDate.now())

                    context.sendDataToPhone("STEPS", 0.0)
                    context.sendDataToPhone("CALORIES", 0.0)
                } else {
                    val latestSteps = passiveDataRepository.latestSteps().first();
                    val latestCalories = passiveDataRepository.latestCalories().first();
                    val latestExerciseCalories = passiveDataRepository.latestExerciseCalories().first();

                    context.sendDataToPhone("STEPS", latestSteps)
                    context.sendDataToPhone("CALORIES", latestCalories + latestExerciseCalories)
                }

//                val at00h00m = it.hours == 0 && it.minutes == 0;
                val at00h05m = it.hours == 0 && it.minutes <= 5;

                Log.d("#### TIME", "${it.hours}:${it.minutes}:${it.seconds}");
//                if (at00h05m) {
//                    val lastDataSyncStrNew = passiveDataRepository.lastDataSync.first();
//                    Log.d("#### LAST SYNC", "$lastDataSyncStr");
//
//                    val formatterNew = DateTimeFormatter.ofPattern("yyyy-MM-dd")
//                    val currentFormatedNew = LocalDate.now().format(formatterNew);
//                    if (lastDataSyncStrNew != null && lastDataSyncStrNew < currentFormatedNew) {
//                        Log.d("#### RS", it.format("dd-MM-yyyy HH:mm"));
//                        passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
//                        passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
//
//                        context.sendDataToPhone("STEPS", 0.0)
//                        context.sendDataToPhone("CALORIES", 0.0)
//                    }
//                }

                true
            }
        }

//        GlobalScope.launch {
//
//            val lastDataSyncStr = passiveDataRepository.lastDataSync.first();
//            Log.d("#### LAST SYNC", "$lastDataSyncStr");
//
//            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
//            val currentFormated = LocalDate.now().format(formatter);
//            if (lastDataSyncStr != null && lastDataSyncStr < currentFormated) {
//                Log.d("#### MANUAL RESET", "$lastDataSyncStr");
//                passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
//                passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
//
//                context.sendDataToPhone("STEPS", 0.0)
//                context.sendDataToPhone("CALORIES", 0.0)
//            }
//
//            while (true) {
//                delay(1000 * 60)
//                Log.e("#### ST", passiveDataRepository.latestSteps().first().toString());
//                Log.e("#### CL", passiveDataRepository.latestCalories().first().toString());
//
//                val latestSteps = passiveDataRepository.latestSteps().first();
//                val latestCalories = passiveDataRepository.latestCalories().first();
//                applicationContext.sendDataToPhone("STEPS", latestSteps)
//                applicationContext.sendDataToPhone("CALORIES", latestCalories)
//
////                val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
////                val minute = Calendar.getInstance().get(Calendar.MINUTE);
////                val second = Calendar.getInstance().get(Calendar.SECOND);
////
////                val at00h05m = hour == 0 && minute <= 5;
////
////                Log.d("#### TIME", "${hour}:${minute}:${second}");
////                if (at00h05m) {
////                    val lastDataSyncStrNew = passiveDataRepository.lastDataSync.first();
////                    Log.d("#### LAST SYNC", "$lastDataSyncStr");
////
////                    val formatterNew = DateTimeFormatter.ofPattern("yyyy-MM-dd")
////                    val currentFormatedNew = LocalDate.now().format(formatterNew);
////                    if (lastDataSyncStrNew != null && lastDataSyncStrNew < currentFormatedNew) {
////                        val currentFormatter = SimpleDateFormat("dd-MM-yyyy HH:mm", Locale.getDefault())
////                        Log.d("#### RS", currentFormatter.format(Date()));
////                        passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
////                        passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
////
////                        applicationContext.sendDataToPhone("STEPS", 0.0)
////                        applicationContext.sendDataToPhone("CALORIES", 0.0)
////                    }
////                }
//
//            }
//        }


        setContent {
            PassiveDataApp(
                healthServicesRepository = healthServicesRepository,
                passiveDataRepository = passiveDataRepository
            )
        }
    }

    override fun onResume() {
        super.onResume()

        scope.launch {
            val passiveDataRepository = (application as MainApplication).passiveDataRepository

            val lastDataSyncStr = passiveDataRepository.lastDataSync.first();
            Log.d("#### LAST SYNC [RESUME]", "$lastDataSyncStr");

            val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
            val currentFormated = LocalDate.now().format(formatter);
            if (lastDataSyncStr != null && lastDataSyncStr < currentFormated) {
                Log.d("#### MANUAL RESET [RESUME]", "$lastDataSyncStr");
                passiveDataRepository.storeLatestSteps(0.0, LocalDate.now())
                passiveDataRepository.storeLatestCalories(0.0, LocalDate.now())
                passiveDataRepository.storeLatestExerciseCalories(0.0, LocalDate.now())

                context.sendDataToPhone("STEPS", 0.0)
                context.sendDataToPhone("CALORIES", 0.0)
            }
        }

    }
}