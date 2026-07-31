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

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import android.widget.Toast
import androidx.health.services.client.PassiveListenerService
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.IntervalDataPoint
import com.singh.fitnesssnacklock.data.PassiveDataRepository
import com.singh.fitnesssnacklock.utils.latestCalories
import com.singh.fitnesssnacklock.utils.latestSteps
import com.google.android.gms.wearable.Wearable
import com.singh.fitnesssnacklock.utils.latestDailyCalories
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.last
import kotlinx.coroutines.runBlocking
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Service to receive data from Health Services.
 *
 * Passive data is delivered from Health Services to this service. Override the appropriate methods
 * in [PassiveListenerService] to receive updates for new data points, goals achieved etc.
 */
class PassiveDataService : PassiveListenerService() {
    private val repository = PassiveDataRepository(this)

    override fun onNewDataPointsReceived(dataPoints: DataPointContainer) {
        runBlocking {
            dataPoints.getData(DataType.STEPS_DAILY).latestSteps()?.let {
                repository.storeLatestSteps(it.toDouble(), LocalDate.now())
                sendDataToPhone("STEPS", it.toDouble());
            }

            dataPoints.getData(DataType.CALORIES_DAILY).latestDailyCalories()?.let {
                Log.d("##### DATA 000", it.toString())
                repository.storeLatestCalories(it, LocalDate.now());
                val exerciseCalories = repository.latestExerciseCalories().first();
                Log.d("##### DATA EXERCISE", exerciseCalories.toString())

                sendDataToPhone("CALORIES", it + exerciseCalories);
            }

            dataPoints.getData(DataType.CALORIES).latestCalories()?.let {
                Log.d("##### DATA 111", it.toString())
                val exerciseCalories = repository.latestExerciseCalories().first();
                repository.storeLatestExerciseCalories(it + exerciseCalories, LocalDate.now());
                Log.d("##### DATA EXERCISE", (it + exerciseCalories).toString())

                val calories = repository.latestCalories().last();
                sendDataToPhone("CALORIES", it + exerciseCalories + calories);
            }

            dataPoints.getData(DataType.CALORIES_TOTAL).let {
                Log.d("##### DATA", it?.total.toString())

            }
        }
    }

    private fun processDataPoint(
        dataPoints: List<IntervalDataPoint<*>>,
        type: String,
    ): Double {
        var latest = 0
        var lastIndex = -1
        val bootInstant =
            Instant.ofEpochMilli(System.currentTimeMillis() - SystemClock.elapsedRealtime())

        if (dataPoints.isNotEmpty()) {
            dataPoints.forEachIndexed { index, intervalDataPoint ->
                val endTime = intervalDataPoint.getEndInstant(bootInstant)
                Log.d("#####", "${type} data index: $index with value: ${intervalDataPoint.value} end time: ${endTime.toEpochMilli()}")
                if (endTime.toEpochMilli() > latest) {
                    latest = endTime.toEpochMilli().toInt()
                    lastIndex = index
                }
            }

            if (lastIndex == -1) return 0.0;

            val latestValue = dataPoints[lastIndex].value;
            if (latestValue is Number) {
                return latestValue.toDouble();
            }

            return 0.0;
        }
        return  0.0
    }

    companion object {
         fun Context.sendDataToPhone(type: String, value: Double) {
            Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
                nodes.forEach { node ->
                    val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
                    val dateFormated = LocalDate.now().format(formatter);

                    Wearable.getMessageClient(this)
                        .sendMessage(
                            node.id,
                            "/watch_connectivity",
                            objectToBytes(mapOf("type" to type, "value" to value.toInt(), "date" to dateFormated))
                        ).addOnSuccessListener {
                            Log.d("#### PHONE", "SENT ${type}:$value");
//                            Toast.makeText(this, "Send $type data to phone", Toast.LENGTH_SHORT)
//                                .show()
                        }
                        .addOnFailureListener {
//                            Toast.makeText(this, "Send failure: ${it.message}", Toast.LENGTH_SHORT)
//                                .show()
                        }
                }
            }
        }

        private fun objectToBytes(`object`: Any): ByteArray {
            val baos = ByteArrayOutputStream()
            val oos = ObjectOutputStream(baos)
            oos.writeObject(`object`)
            return baos.toByteArray()
        }
    }
}
