package com.example.piliplus

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

// The in-app update: opens a downloaded APK in the system installer. Before
// that it compares the APK with the installed app, because the installer only
// says "App not installed" when the signature or version doesn't fit.
//
// The handler holds the activity, and the engine can outlive it (audio keeps
// playing in the background): MainActivity registers it when the engine
// attaches and unregisters it in cleanUpFlutterEngine.
class AppInstaller(private val activity: Activity) {
    companion object {
        fun unregister(messenger: BinaryMessenger) {
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(null)
        }

        private const val CHANNEL = "PiliPlus/installer"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstall())
                "openSettings" -> result.success(openSettings())
                "install" -> result.success(install(call.argument<String>("path")!!))
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    // "started", or why it can't install: "permission", "invalid",
    // "signature", "downgrade", "failed"
    private fun install(path: String): String {
        val file = File(path)
        val pm = activity.packageManager
        @Suppress("DEPRECATION")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val archive = pm.getPackageArchiveInfo(file.path, flags)
        if (archive == null || archive.packageName != activity.packageName) return "invalid"
        val installed = pm.getPackageInfo(activity.packageName, flags)
        val archiveSigners = signers(archive)
        if (archiveSigners.isNotEmpty() && archiveSigners.none(signers(installed)::contains)) {
            return "signature"
        }
        if (versionCode(archive) < versionCode(installed)) return "downgrade"
        if (!canInstall()) return "permission"
        return try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.update", file)
            activity.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            "started"
        } catch (_: Exception) {
            "failed"
        }
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): List<Signature> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.let {
                if (it.hasMultipleSigners()) it.apkContentsSigners else it.signingCertificateHistory
            }?.toList()
        } else {
            info.signatures?.toList()
        } ?: emptyList()

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
}
