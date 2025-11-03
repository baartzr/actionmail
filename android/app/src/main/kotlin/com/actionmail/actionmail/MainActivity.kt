package com.actionmail.actionmail

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.actionmail.actionmail/bringToFront"
    private val APP_LINK_CHANNEL = "com.actionmail.actionmail/appLink"
    private var appLinkEventSink: EventChannel.EventSink? = null
    private var pendingAppLink: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("MainActivity", "onCreate called, intent=${intent}, intent.data=${intent?.data}")
        if (intent?.data != null) {
            Log.d("MainActivity", "onCreate: intent has data=${intent.data}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called, intent=${intent}, intent.data=${intent?.data}")
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToFront" -> {
                    bringToFront()
                    result.success(null)
                }
                "getInitialAppLink" -> {
                    Log.d("MainActivity", "getInitialAppLink called, pendingAppLink=$pendingAppLink")
                    // Also check current intent
                    val currentIntentUri = intent?.data?.toString()
                    Log.d("MainActivity", "current intent data=$currentIntentUri")
                    // Check both pending and current intent
                    val link = when {
                        pendingAppLink != null -> pendingAppLink
                        currentIntentUri != null && currentIntentUri.contains("inboxiq--api.web.app") -> {
                            // Also extract code parameter to verify it's an OAuth callback
                            val uri = intent?.data
                            if (uri != null && uri.getQueryParameter("code") != null) {
                                currentIntentUri
                            } else null
                        }
                        else -> null
                    }
                    // Don't clear yet - only clear when explicitly requested or after successful processing
                    Log.d("MainActivity", "returning link=$link")
                    result.success(link)
                }
                "clearAppLink" -> {
                    Log.d("MainActivity", "clearAppLink called")
                    pendingAppLink = null
                    // Clear intent data
                    intent?.data = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        
        // Event channel for App Links (when app is already running)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, APP_LINK_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    appLinkEventSink = events
                    // Send initial intent URL if app was opened via App Link and app is already running
                    handleIntent(intent, true)
                }

                override fun onCancel(arguments: Any?) {
                    appLinkEventSink = null
                }
            }
        )
        
        // Check initial intent when engine is configured
        handleIntent(intent, false)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, true)
    }
    
    private fun handleIntent(intent: Intent?, isNewIntent: Boolean) {
        Log.d("MainActivity", "handleIntent called, intent=$intent, isNewIntent=$isNewIntent")
        Log.d("MainActivity", "intent.data=${intent?.data}, intent.action=${intent?.action}")
        if (intent?.data != null && intent.action == Intent.ACTION_VIEW) {
            val uri = intent.data
            Log.d("MainActivity", "uri=$uri, scheme=${uri?.scheme}, host=${uri?.host}")
            if (uri != null && uri.scheme == "https" && uri.host == "inboxiq--api.web.app") {
                val url = uri.toString()
                Log.d("MainActivity", "App Link detected: $url, isNewIntent=$isNewIntent, appLinkEventSink=${appLinkEventSink != null}")
                if (isNewIntent && appLinkEventSink != null) {
                    // App is running - send via EventChannel
                    Log.d("MainActivity", "Sending via EventChannel")
                    appLinkEventSink?.success(url)
                } else {
                    // App was killed/restarted - store for getInitialAppLink
                    Log.d("MainActivity", "Storing pendingAppLink=$url")
                    pendingAppLink = url
                }
            } else {
                Log.d("MainActivity", "URI does not match App Link criteria")
            }
        } else {
            Log.d("MainActivity", "Intent does not have data or is not ACTION_VIEW")
        }
    }

    private fun bringToFront() {
        // Try moving existing task to front
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val tasks = activityManager.appTasks
            if (!tasks.isNullOrEmpty()) {
                try {
                    tasks.first().moveToFront()
                    return
                } catch (_: Exception) { /* fall through */ }
            }
        }
        // Fallback: explicitly start MainActivity to bring app to foreground without chooser
        try {
            val intent = Intent(this, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (_: Exception) { /* ignore */ }
    }
}
