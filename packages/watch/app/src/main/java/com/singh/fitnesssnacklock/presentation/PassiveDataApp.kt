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
package com.singh.fitnesssnacklock.presentation

import android.widget.Toast
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.health.services.client.data.DataType
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.TimeText
import com.singh.fitnesssnacklock.PERMISSION
import com.singh.fitnesssnacklock.data.HealthServicesRepository
import com.singh.fitnesssnacklock.data.PassiveDataRepository
import com.singh.fitnesssnacklock.theme.PassiveDataTheme
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.rememberPermissionState
import com.google.android.gms.wearable.Wearable
import com.singh.fitnesssnacklock.service.PassiveDataService.Companion.sendDataToPhone
import com.singh.fitnesssnacklock.utils.latestCalories
import com.singh.fitnesssnacklock.utils.latestSteps
import kotlinx.coroutines.flow.last
import kotlinx.coroutines.runBlocking
import java.time.LocalDate

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun PassiveDataApp(
    healthServicesRepository: HealthServicesRepository,
    passiveDataRepository: PassiveDataRepository
) {
    PassiveDataTheme {
        val context = LocalContext.current
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            timeText = { TimeText() }
        ) {
            val viewModel: PassiveDataViewModel = viewModel(
                factory = PassiveDataViewModelFactory(
                    healthServicesRepository = healthServicesRepository,
                    passiveDataRepository = passiveDataRepository
                )
            )
            val stepsValue by viewModel.stepsValue.collectAsState()
            val caloriesValue by viewModel.caloriesValue.collectAsState()
            val exerciseCaloriesValue by viewModel.exerciseCaloriesValue.collectAsState()
            val uiState by viewModel.uiState

            if (uiState == UiState.Supported) {
                val permissionState = rememberPermissionState(
                    permission = PERMISSION,
                    onPermissionResult = { granted ->
                        if (granted) viewModel.toggleEnabled()
                    }
                )
                PassiveDataScreen(
                    stepVal = stepsValue,
                    calorieVal = caloriesValue + exerciseCaloriesValue,
                    onSync = {
                        val latestSteps = viewModel.stepsValue.value;
                        val latestCalories = viewModel.caloriesValue.value + viewModel.exerciseCaloriesValue.value;

                        if (latestSteps == 0.0 && latestCalories == 0.0) {
                            runBlocking {
                                passiveDataRepository.storeLatestSteps(0.0, LocalDate.now());
                                passiveDataRepository.storeLatestCalories(0.0, LocalDate.now());
                                passiveDataRepository.storeLatestExerciseCalories(0.0, LocalDate.now());

                                context.sendDataToPhone("STEPS", 0.0);
                                context.sendDataToPhone("CALORIES", 0.0);
                            }

                        } else {
                            context.sendDataToPhone("STEPS", stepsValue);
                            context.sendDataToPhone("CALORIES", caloriesValue + exerciseCaloriesValue);
                        }

                    },
                    permissionState = permissionState
                )
            } else if (uiState == UiState.NotSupported) {
                NotSupportedScreen()
            }
        }
    }
}
