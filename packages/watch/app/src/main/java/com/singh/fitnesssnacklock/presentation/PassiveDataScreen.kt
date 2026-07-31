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

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Devices
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.health.services.client.data.DataType
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonColors
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.OutlinedButton
import androidx.wear.compose.material.Text
import com.singh.fitnesssnacklock.PERMISSION
import com.singh.fitnesssnacklock.theme.PassiveDataTheme
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.PermissionState
import com.google.accompanist.permissions.PermissionStatus
import com.google.accompanist.permissions.isGranted
import com.singh.fitnesssnacklock.service.PassiveDataService
import com.singh.fitnesssnacklock.service.PassiveDataService.Companion.sendDataToPhone

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun PassiveDataScreen(
    stepVal: Double,
    calorieVal: Double,
    onSync: () -> Unit,
    permissionState: PermissionState,

    ) {

    Column(
        modifier = Modifier
            .padding(all = 16.dp)
            .verticalScroll(rememberScrollState())
        ,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        when {
            !permissionState.status.isGranted -> {
                Text("")
            }
            (stepVal != 0.0 || calorieVal != 0.0) -> {
                Text(
                    "syncing...",
                    modifier = Modifier.padding(top = 12.dp, bottom = 8.dp),
                    fontStyle = FontStyle.Italic,
                )
            }
            else -> {
                Text(
                    "walk to sync",
                    modifier = Modifier.padding(top = 12.dp, bottom = 8.dp),
                    fontStyle = FontStyle.Italic,
                )
            }
        }
        Row() {
            StepsCard(
                modifier = Modifier
                    .weight(5F)
                    .padding(end = 4.dp),
                value = stepVal
            )
            CaloriesCard(
                modifier = Modifier
                    .weight(4F)
                    .padding(start = 4.dp),
                value = calorieVal
            )
        }
        when {
            !permissionState.status.isGranted -> {
                Button(
                    modifier = Modifier
                        .padding(top = 12.dp, bottom = 8.dp)
                        .width(200.dp)
                        .height(48.dp),
                    shape = RoundedCornerShape(5.dp),
                    colors = ButtonDefaults.primaryButtonColors(backgroundColor = Color.Transparent),
                    onClick = {
                        permissionState.launchPermissionRequest()
                    }
                ) {
                    Text(
                        "REQUEST",
                        fontWeight = FontWeight(500)
                    )
                }
            }
            (stepVal != 0.0 || calorieVal != 0.0) -> {
                Button(
                    modifier = Modifier
                        .padding(top = 8.dp, bottom = 8.dp)
                        .width(200.dp)
                        .height(48.dp),
                    shape = RoundedCornerShape(5.dp),
                    colors = ButtonDefaults.primaryButtonColors(backgroundColor = Color.Transparent),
                    onClick = {
                        onSync();
                    }
                ) {
                    Text(
                        "SEND",
                        fontWeight = FontWeight(500)
                    )
                }
            }
            else -> {
                Button(
                    modifier = Modifier
                        .padding(top = 8.dp, bottom = 8.dp)
                        .width(200.dp)
                        .height(48.dp),
                    shape = RoundedCornerShape(5.dp),
                    colors = ButtonDefaults.primaryButtonColors(backgroundColor = Color.Transparent),
                    onClick = {
                        onSync();
                    }
                ) {
                    Text(
                        "SEND",
                        fontWeight = FontWeight(500)
                    )
                }
            }
        }
    }
}

@ExperimentalPermissionsApi
@Preview(
    device = Devices.WEAR_OS_SMALL_ROUND,
    showBackground = true,
    showSystemUi = true
)
@Composable
fun PassiveDataScreenPreview() {
    val permissionState = object : PermissionState {
        override val permission = PERMISSION
        override val status: PermissionStatus = PermissionStatus.Granted
        override fun launchPermissionRequest() {}
    }
    PassiveDataTheme {
        PassiveDataScreen(
            stepVal = 65.6,
            calorieVal = 65.6,
            onSync = {},
            permissionState = permissionState
        )
    }
}
