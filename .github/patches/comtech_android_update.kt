// Comtech: the Android side of app updates (see comtech_update.dart). The app
// downloads the APK into its cache; this opens Android's installer for it.
package com.carriez.flutter_hbb

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.io.File

private const val COMTECH_UPDATE_CHANNEL = "comtech_update"
private const val COMTECH_UPDATE_NOTIFICATION = 7701

fun comtechInstallApk(activity: Activity, path: String) {
    // MainActivity can be opened by other apps: only the app's own download
    // folder is installed from
    val dir = File(activity.cacheDir, "comtech-update").canonicalPath + File.separator
    if (!File(path).canonicalPath.startsWith(dir)) return
    // the user has to allow this app to install apps once; they tap Install
    // again afterwards
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
        val settings = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName))
        settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(settings)
        return
    }
    val uri = FileProvider.getUriForFile(activity, activity.packageName + ".comtech_update", File(path))
    val install = Intent(Intent.ACTION_VIEW)
    install.setDataAndType(uri, "application/vnd.android.package-archive")
    install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    activity.startActivity(install)
}

fun comtechUpdateNotify(context: Context, version: String, path: String) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(COMTECH_UPDATE_CHANNEL) == null) {
        manager.createNotificationChannel(
            NotificationChannel(COMTECH_UPDATE_CHANNEL, "Updates", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }
    val open = Intent(context, MainActivity::class.java)
    open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    open.putExtra("comtech_install_apk", path)
    val tap = PendingIntent.getActivity(context, COMTECH_UPDATE_NOTIFICATION, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    val notification = NotificationCompat.Builder(context, COMTECH_UPDATE_CHANNEL)
        .setSmallIcon(R.mipmap.ic_stat_logo)
        .setContentTitle("Update available")
        .setContentText("Tap to install version $version")
        .setContentIntent(tap)
        .setAutoCancel(true)
        .build()
    manager.notify(COMTECH_UPDATE_NOTIFICATION, notification)
}
