package __PKG__

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** کانال Flutter ↔ اندروید برای به‌روزرسانی درجا (in-place) از GitHub Releases. */
object UpdateChannel {
    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "nexora/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "appInfo" -> {
                        @Suppress("DEPRECATION")
                        val pi = activity.packageManager.getPackageInfo(activity.packageName, 0)
                        @Suppress("DEPRECATION")
                        val code: Long = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
                        result.success(
                            mapOf(
                                "versionName" to (pi.versionName ?: ""),
                                "versionCode" to code,
                                "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                            )
                        )
                    }
                    "start" -> {
                        val url = call.argument<String>("url") ?: ""
                        val version = call.argument<String>("version") ?: ""
                        if (url.isEmpty()) { result.error("bad_args", "url is empty", null); return@setMethodCallHandler }
                        if (Build.VERSION.SDK_INT >= 33 &&
                            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            // برای نمایش پیشرفت در نوتیفیکیشن؛ دانلود بدون آن هم کار می‌کند
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7342)
                        }
                        val i = Intent(activity, UpdateService::class.java)
                            .putExtra(UpdateService.EXTRA_URL, url)
                            .putExtra(UpdateService.EXTRA_VERSION, version)
                            .putExtra(UpdateService.EXTRA_TOKEN, call.argument<String>("token") ?: "")
                        if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(i) else activity.startService(i)
                        result.success(null)
                    }
                    "status" -> {
                        UpdateState.restore(activity)
                        result.success(UpdateState.toMap())
                    }
                    "cancel" -> {
                        UpdateService.cancelRequested = true
                        if (!UpdateService.running) UpdateState.reset(activity)
                        result.success(null)
                    }
                    "clear" -> {
                        UpdateService.updatesDir(activity).listFiles()?.forEach { it.delete() }
                        UpdateState.reset(activity)
                        result.success(null)
                    }
                    "install" -> {
                        UpdateState.restore(activity)
                        val path = UpdateState.path
                        val file = File(path)
                        if (UpdateState.status != "done" || path.isEmpty() || !file.exists()) {
                            result.success("no_file"); return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            val s = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName))
                            s.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            activity.startActivity(s)
                            result.success("need_permission"); return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".updatefp", file)
                        val i = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(i)
                        result.success("ok")
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update_error", e.message, null)
            }
        }
    }
}
