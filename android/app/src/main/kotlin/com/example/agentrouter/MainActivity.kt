package com.example.agentrouter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingAutorun = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        pendingAutorun = intent?.getBooleanExtra("autorun", false) == true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("autorun", false)) channel?.invokeMethod("autorun", null)
    }

    private fun collectWebViews(v: View, out: MutableList<WebView>) {
        if (v is WebView) { out.add(v); return }
        if (v is ViewGroup) for (i in 0 until v.childCount) collectWebViews(v.getChildAt(i), out)
    }

    /** Sends a real touch down/up to the visible WebView (coords are view-local, physical px). */
    private fun tapWebView(x: Float, y: Float): Boolean {
        val all = mutableListOf<WebView>()
        collectWebViews(window.decorView, all)
        val wv = all
            .filter { it.isShown && it.width > 0 && it.height > 0 && it.getGlobalVisibleRect(Rect()) }
            .maxByOrNull { it.width * it.height } ?: return false
        val t = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, y, 0)
        down.source = InputDevice.SOURCE_TOUCHSCREEN
        wv.dispatchTouchEvent(down)
        down.recycle()
        Handler(Looper.getMainLooper()).postDelayed({
            val up = MotionEvent.obtain(t, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x, y, 0)
            up.source = InputDevice.SOURCE_TOUCHSCREEN
            wv.dispatchTouchEvent(up)
            up.recycle()
        }, 80)
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "autostart")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    Autostart.schedule(this, call.argument<Int>("hour")!!, call.argument<Int>("minute")!!)
                    result.success(null)
                }
                "cancel" -> { Autostart.cancel(this); result.success(null) }
                "consumeAutorun" -> { val v = pendingAutorun; pendingAutorun = false; result.success(v) }
                "canOverlay" ->
                    result.success(Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                    )
                    result.success(null)
                }
                "tap" -> {
                    val x = call.argument<Double>("x")!!.toFloat()
                    val y = call.argument<Double>("y")!!.toFloat()
                    result.success(tapWebView(x, y))
                }
                "bringToFront" -> { Autostart.launchApp(this, false); result.success(null) }
                "canFullScreen" -> {
                    val nm = getSystemService(android.app.NotificationManager::class.java)
                    result.success(Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent())
                }
                "openFullScreenSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName")
                            )
                        )
                    }
                    result.success(null)
                }
                "keepAwake" -> {
                    if (call.argument<Boolean>("on") == true)
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}