package com.example.mapped_app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mapped_app/platform_config",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGoogleDriveServerClientId" -> {
                    val applicationInfo = packageManager.getApplicationInfo(
                        packageName,
                        android.content.pm.PackageManager.GET_META_DATA,
                    )
                    val serverClientId = applicationInfo.metaData
                        ?.getString("com.mapped.drive.SERVER_CLIENT_ID")
                        ?.trim()
                        .orEmpty()
                    result.success(serverClientId)
                }

                else -> result.notImplemented()
            }
        }
    }
}
