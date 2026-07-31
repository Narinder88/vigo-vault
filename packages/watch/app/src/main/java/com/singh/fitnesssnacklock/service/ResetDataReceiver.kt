package com.singh.fitnesssnacklock.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar


fun scheduleAlarm(context: Context) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val intent = Intent(context, ResetDataReceiver::class.java)
    val pendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // Set the time for 00:00 AM
    val calendar = Calendar.getInstance()
    calendar.set(Calendar.HOUR_OF_DAY, 0)
    calendar.set(Calendar.MINUTE, 0)
    calendar.set(Calendar.SECOND, 0)

    // If it's already past 00:00 AM today, set it for tomorrow
    if (Calendar.getInstance().after(calendar)) {
        calendar.add(Calendar.DAY_OF_MONTH, 1)
    }

    val testTime = Calendar.getInstance();
    testTime.set(Calendar.MINUTE, 30);

    // Schedule the alarm to repeat daily at 00:00 AM
    alarmManager.setRepeating(
        AlarmManager.RTC_WAKEUP,
        testTime.timeInMillis,
        AlarmManager.INTERVAL_DAY,
        pendingIntent
    )
}

class ResetDataReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AAAAA", "SSSS");
    }
}
