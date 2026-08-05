package com.singh.fitnessssnacklock.wear

import android.app.Application
import com.singh.fitnessssnacklock.wear.data.LockConfigRepository

class WearLockApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        LockConfigRepository.getInstance(this)
    }
}
