package com.singh.fitnessssnacklock.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.singh.fitnessssnacklock.wear.ui.UnlockScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            UnlockScreen()
        }
    }
}
