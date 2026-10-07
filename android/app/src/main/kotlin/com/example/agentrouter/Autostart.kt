package com.example.agentrouter

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import java.util.Calendar

object Autostart {
    private const val PREFS = "autostart"

    private fun alarmIntent(ctx: Context) = PendingIntent.getBroadcast(
        ctx, 7001, Intent(ctx, AutostartReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    /**
     * Opens the app in the foreground from the background. A 1px invisible overlay
     * window is shown first: a visible window is what lets Android 10-15 allow
     * the activity start (needs "Display over other apps").
     */
    fun launchApp(ctx: Context, autorun: Boolean, done: (() -> Unit)? = null) {
        val app = ctx.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        var overlay: View? = null
        try {
            if (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(app)) {
                val type = if (Build.VERSION.SDK_INT >= 26)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
                val lp = WindowManager.LayoutParams(
                    1, 1, type,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT
                )
                overlay = View(app).also { wm.addView(it, lp) }
            }
        } catch (_: Exception) {
            overlay = null
        }
        try {
            val i = Intent(app, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            if (autorun) i.putExtra("autorun", true)
            app.startActivity(i)
        } catch (_: Exception) {
            // blocked: the full-screen notification fallback still fires
        }
        Handler(Looper.getMainLooper()).postDelayed({
            try { overlay?.let { wm.removeView(it) } } catch (_: Exception) {}
            done?.invoke()
        }, 6000)
    }

    fun schedule(ctx: Context, hour: Int, minute: Int) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("on", true).putInt("h", hour).putInt("m", minute).apply()
        arm(ctx, hour, minute)
    }

    fun cancel(ctx: Context) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("on", false).apply()
        (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(alarmIntent(ctx))
    }

    /** Re-arms the next occurrence if autostart is on (boot, time change, after firing). */
    fun rearm(ctx: Context) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (p.getBoolean("on", false)) arm(ctx, p.getInt("h", 18), p.getInt("m", 30))
    }

    private fun arm(ctx: Context, hour: Int, minute: Int) {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        // strictly in the future (60s margin so the alarm that just fired is not re-armed for "now")
        if (cal.timeInMillis <= System.currentTimeMillis() + 60_000) cal.add(Calendar.DAY_OF_YEAR, 1)

        val show = PendingIntent.getActivity(
            ctx, 7002, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // setAlarmClock needs no exact-alarm permission and is exempt from Doze.
        (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
            .setAlarmClock(AlarmManager.AlarmClockInfo(cal.timeInMillis, show), alarmIntent(ctx))
    }
}

class AutostartReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Autostart.rearm(ctx) // tomorrow first, so a failure below never kills the schedule
        val pending = goAsync() // keep the process alive while the overlay is up
        Autostart.launchApp(ctx, true) { pending.finish() }
    }
}

class AutostartBootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) = Autostart.rearm(ctx)
}