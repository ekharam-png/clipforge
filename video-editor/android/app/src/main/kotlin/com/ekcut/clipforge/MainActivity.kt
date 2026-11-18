package com.ekcut.clipforge

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import java.io.File
import android.os.StatFs
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // "Find file…" > "Search the gallery" (lib/ui/gallery_search.dart):
    // the result waiting for the permission answer.
    private var pendingFind: Pair<String, MethodChannel.Result>? = null

    private fun galleryPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= 33) arrayOf(
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_AUDIO,
        ) else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)

    private fun hasGalleryAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= 34 && checkSelfPermission(
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
            ) == PackageManager.PERMISSION_GRANTED) return true
        return galleryPermissions().any {
            checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    // Files on the phone whose name is [name] (any case), newest first.
    private fun findInGallery(name: String): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val collection = MediaStore.Files.getContentUri("external")
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        if (Build.VERSION.SDK_INT >= 29) projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
        contentResolver.query(
            collection,
            projection.toTypedArray(),
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
            arrayOf(name),
            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
        )?.use { c ->
            while (c.moveToNext() && out.size < 20) {
                val id = c.getLong(0)
                val folder = if (Build.VERSION.SDK_INT >= 29) c.getString(4) else null
                out.add(mapOf(
                    "uri" to ContentUris.withAppendedId(collection, id).toString(),
                    "name" to c.getString(1),
                    "size" to c.getLong(2),
                    "modified" to c.getLong(3) * 1000,
                    "folder" to folder,
                ))
            }
        }
        return out
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != GALLERY_REQUEST) return
        val (name, result) = pendingFind ?: return
        pendingFind = null
        if (!hasGalleryAccess()) {
            result.error("permission", "No access to photos and videos", null)
            return
        }
        try {
            result.success(findInGallery(name))
        } catch (e: Exception) {
            result.error("gallery", e.toString(), null)
        }
    }

    companion object {
        private const val GALLERY_REQUEST = 4711
    }

    // The desktop_drop plugin (drag and drop of files on computers) also
    // registers on Android and accepts every drag onto the window. Phones
    // get no drag and drop in ClipForge, so the system default is put back.
    override fun onStart() {
        super.onStart()
        findViewById<ViewGroup>(android.R.id.content)?.setOnDragListener(null)
    }

    // Long exports (lib/ui/long_jobs.dart): free space on the disk the
    // video goes to, and the export service that keeps the app running.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Copy version info" (lib/ui/about.dart): which phone this is.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clipforge/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    result.success(mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "release" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT,
                    ))
                } else {
                    result.notImplemented()
                }
            }
        // Updates (lib/ui/update): open a web page, and hand a downloaded,
        // checked APK to the system installer. Android asks the user to
        // confirm; the first time it also asks to allow installs from
        // ClipForge.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clipforge/update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openUrl" -> {
                            startActivity(Intent(Intent.ACTION_VIEW,
                                Uri.parse(call.argument<String>("url")))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        }
                        "installApk" -> {
                            val file = File(call.argument<String>("path")!!)
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this, "$packageName.updates", file)
                            startActivity(Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    or Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        }
                        "is64Bit" -> result.success(
                            Build.SUPPORTED_64_BIT_ABIS.isNotEmpty() &&
                                android.os.Process.is64Bit())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("update", e.toString(), null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clipforge/gallery")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "find" -> {
                            val name = call.argument<String>("name") ?: ""
                            if (hasGalleryAccess()) {
                                result.success(findInGallery(name))
                            } else {
                                pendingFind?.second?.error("cancelled", "Replaced", null)
                                pendingFind = Pair(name, result)
                                requestPermissions(galleryPermissions(), GALLERY_REQUEST)
                            }
                        }
                        "copy" -> {
                            val uri = Uri.parse(call.argument<String>("uri"))
                            val target = File(call.argument<String>("path")!!)
                            target.parentFile?.mkdirs()
                            Thread {
                                try {
                                    contentResolver.openInputStream(uri)!!.use { input ->
                                        target.outputStream().use { input.copyTo(it, 64 * 1024) }
                                    }
                                    runOnUiThread { result.success(target.length()) }
                                } catch (e: Exception) {
                                    target.delete()
                                    runOnUiThread { result.error("copy", e.toString(), null) }
                                }
                            }.start()
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("gallery", e.toString(), null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clipforge/long_jobs")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "freeBytes" -> {
                            val path = call.argument<String>("path") ?: filesDir.path
                            result.success(StatFs(path).availableBytes)
                        }
                        "startExport" -> {
                            val intent = Intent(this, ExportService::class.java)
                                .putExtra(ExportService.EXTRA_TITLE,
                                    call.argument<String>("title"))
                                .putExtra(ExportService.EXTRA_TEXT,
                                    call.argument<String>("text"))
                            if (Build.VERSION.SDK_INT >= 26) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            result.success(true)
                        }
                        "stopExport" -> {
                            stopService(Intent(this, ExportService::class.java))
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // E.g. a foreground service may not be started from the
                    // background: the export still runs, only less protected.
                    result.error("long_jobs", e.toString(), null)
                }
            }
    }
}
