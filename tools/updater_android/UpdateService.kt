package __PKG__

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/** وضعیت دانلود؛ در SharedPreferences هم ذخیره می‌شود تا بعد از بسته شدن برنامه قابل خواندن باشد. */
object UpdateState {
    @Volatile var status = "idle" // idle | downloading | done | error
    @Volatile var received = 0L
    @Volatile var total = 0L
    @Volatile var version = ""
    @Volatile var path = ""
    @Volatile var error = ""

    private const val PREFS = "nexora_update"

    fun toMap(): Map<String, Any> = mapOf(
        "state" to status,
        "received" to received,
        "total" to total,
        "version" to version,
        "path" to path,
        "error" to error,
    )

    @Synchronized
    fun save(ctx: Context) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("status", status).putLong("received", received).putLong("total", total)
            .putString("version", version).putString("path", path).putString("error", error)
            .apply()
    }

    /** بعد از مرگ پروسه: وضعیت ذخیره‌شده را برمی‌گرداند و حالت‌های ناقص را درست می‌کند. */
    @Synchronized
    fun restore(ctx: Context) {
        if (UpdateService.running) return
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        status = p.getString("status", "idle") ?: "idle"
        received = p.getLong("received", 0L)
        total = p.getLong("total", 0L)
        version = p.getString("version", "") ?: ""
        path = p.getString("path", "") ?: ""
        error = p.getString("error", "") ?: ""
        if (status == "downloading") { // سرویس دیگر زنده نیست
            status = "error"; error = "interrupted"
        }
        if (status == "done" && (path.isEmpty() || !File(path).exists())) {
            status = "idle"; path = ""
        }
    }

    @Synchronized
    fun reset(ctx: Context) {
        status = "idle"; received = 0; total = 0; version = ""; path = ""; error = ""
        save(ctx)
    }
}

/**
 * Foreground Service از نوع dataSync: دانلود APK حتی وقتی کاربر از برنامه خارج شود ادامه پیدا می‌کند
 * و پیشرفت در نوتیفیکیشن نشان داده می‌شود.
 */
class UpdateService : Service() {
    companion object {
        @Volatile var running = false
        @Volatile var cancelRequested = false
        const val CHANNEL = "nexora_update"
        const val ID_PROGRESS = 7341
        const val ID_DONE = 7342
        const val EXTRA_URL = "url"
        const val EXTRA_VERSION = "version"
        const val EXTRA_TOKEN = "token"

        fun updatesDir(ctx: Context): File =
            File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "updates").also { it.mkdirs() }
    }

    private var worker: Thread? = null
    @Volatile private var authToken: String = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val url = intent?.getStringExtra(EXTRA_URL)
        val version = intent?.getStringExtra(EXTRA_VERSION) ?: ""
        authToken = intent?.getStringExtra(EXTRA_TOKEN) ?: ""
        if (url.isNullOrEmpty()) {
            stopSelf(); return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        running = true
        cancelRequested = false
        ensureChannel()
        val first = buildProgress(0, 0, 0L, true)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID_PROGRESS, first, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID_PROGRESS, first)
        }
        UpdateState.status = "downloading"
        UpdateState.received = 0; UpdateState.total = 0
        UpdateState.version = version; UpdateState.path = ""; UpdateState.error = ""
        UpdateState.save(this)
        worker = Thread { download(url, version) }.also { it.start() }
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "App update", NotificationManager.IMPORTANCE_LOW)
                )
            }
        }
    }

    private fun builder(): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)

    private fun smallIcon(): Int {
        val id = resources.getIdentifier("ic_stat_logo", "drawable", packageName)
        return if (id != 0) id else android.R.drawable.stat_sys_download
    }

    private fun openAppIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun buildProgress(percent: Int, max: Int, received: Long, indeterminate: Boolean): Notification {
        val text = if (indeterminate) "Preparing download…" else "$percent% downloaded"
        return builder()
            .setSmallIcon(smallIcon())
            .setContentTitle("Nexora VPN update")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .setProgress(if (indeterminate) 0 else 100, percent, indeterminate)
            .build()
    }

    private fun notifyFinal(title: String, text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        val n = builder()
            .setSmallIcon(smallIcon())
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()
        try { nm.notify(ID_DONE, n) } catch (e: Exception) {}
    }

    private fun open(url: String, from: Long): HttpURLConnection {
        // ریپوی خصوصی: آدرس API دارایی با توکن باز می‌شود؛ ریدایرکت (S3) بدون هدر Authorization دنبال می‌شود.
        var target = url
        val useAuth = authToken.isNotEmpty() && url.startsWith("https://api.github.com/")
        var hops = 0
        while (true) {
            val c = URL(target).openConnection() as HttpURLConnection
            c.connectTimeout = 20000
            c.readTimeout = 30000
            c.instanceFollowRedirects = !useAuth
            c.setRequestProperty("User-Agent", "NexoraVPN-Updater")
            if (useAuth && hops == 0) {
                c.setRequestProperty("Authorization", "Bearer $authToken")
                c.setRequestProperty("Accept", "application/octet-stream")
            }
            if (from > 0) c.setRequestProperty("Range", "bytes=$from-")
            if (!useAuth) return c
            val code = c.responseCode
            if (code in 300..399 && hops < 5) {
                val loc = c.getHeaderField("Location")
                c.disconnect()
                if (loc.isNullOrEmpty()) return c
                target = loc
                hops++
                continue
            }
            return c
        }
    }

    private fun download(url: String, version: String) {
        val dir = updatesDir(this)
        val safe = version.replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "latest" }
        val target = File(dir, "nexora-$safe.apk")
        val part = File(dir, "nexora-$safe.apk.part")
        dir.listFiles()?.forEach {
            if (it.name != target.name && it.name != part.name) it.delete()
        }
        var conn: HttpURLConnection? = null
        try {
            var existing = if (part.exists()) part.length() else 0L
            conn = open(url, existing)
            var code = conn.responseCode
            if (code == 416) { // فایل ناقص قدیمی معتبر نیست
                conn.disconnect(); part.delete(); existing = 0
                conn = open(url, 0); code = conn.responseCode
            }
            if (code != 200 && code != 206) throw RuntimeException("HTTP $code")
            val append = code == 206 && existing > 0
            if (!append) existing = 0
            val len = conn.contentLengthLong
            val total = if (len > 0) existing + len else 0L
            var received = existing
            UpdateState.total = total
            var lastTick = 0L
            conn.inputStream.use { input ->
                FileOutputStream(part, append).use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        if (cancelRequested) throw InterruptedException("cancelled")
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        received += n
                        val now = System.currentTimeMillis()
                        if (now - lastTick > 400) {
                            lastTick = now
                            UpdateState.received = received
                            val pct = if (total > 0) ((received * 100) / total).toInt().coerceIn(0, 100) else 0
                            val nm = getSystemService(NotificationManager::class.java)
                            try { nm.notify(ID_PROGRESS, buildProgress(pct, 100, received, total <= 0)) } catch (e: Exception) {}
                        }
                    }
                }
            }
            if (total > 0 && received != total) throw RuntimeException("incomplete download")
            if (target.exists()) target.delete()
            if (!part.renameTo(target)) throw RuntimeException("cannot save file")
            // فقط APK همین برنامه (همان package) پذیرفته می‌شود
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageArchiveInfo(target.absolutePath, 0)
            if (info == null || info.packageName != packageName) {
                target.delete()
                throw RuntimeException("invalid apk")
            }
            UpdateState.received = received
            UpdateState.total = if (total > 0) total else received
            UpdateState.path = target.absolutePath
            UpdateState.status = "done"
            UpdateState.error = ""
            UpdateState.save(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            notifyFinal("Update downloaded", "Open Nexora VPN to install the update")
        } catch (e: InterruptedException) {
            part.delete()
            UpdateState.status = "idle"; UpdateState.received = 0; UpdateState.total = 0
            UpdateState.save(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            UpdateState.status = "error"
            UpdateState.error = e.message ?: "download failed"
            UpdateState.save(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            notifyFinal("Update failed", "Open Nexora VPN and try again")
        } finally {
            try { conn?.disconnect() } catch (e: Exception) {}
            running = false
            stopSelf()
        }
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
