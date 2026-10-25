package com.yash.xpenc.conectr

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens XPENC after a pull (see xpenc_launcher.dart). Only packages
        // listed under <queries> in the manifest are visible here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "conectr/apps")
            .setMethodCallHandler { call, result ->
                val launch = (call.arguments as? String)
                    ?.let { packageManager.getLaunchIntentForPackage(it) }
                when (call.method) {
                    "isInstalled" -> result.success(launch != null)
                    "launch" -> {
                        if (launch != null) startActivity(launch)
                        result.success(launch != null)
                    }
                    else -> result.notImplemented()
                }
            }
        // The friends list XPENC may read (see friends_cache.dart and
        // XpencProvider).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "conectr/friends_cache")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        XpencProvider.publish(applicationContext, call.arguments as String)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
