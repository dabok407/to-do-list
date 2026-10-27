package com.dabok407.hangeoreum

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** User-initiated file picker only. Automatic backups remain in app-private files. */
class BackupDocumentBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.dabok407.hangeoreum/backup")
    private var pending: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private var exporting = false
    private val maxBytes = 20 * 1024 * 1024
    private val requestCode = 7814

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "export" && call.method != "import") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("backup_busy", "A file picker is already open.", null)
            } else {
                try {
                    exporting = call.method == "export"
                    val intent = if (exporting) {
                        val contents = call.argument<String>("contents")
                            ?: throw IllegalArgumentException("Backup data is missing.")
                        if (contents.length > maxBytes) throw IllegalArgumentException("Backup file is too large.")
                        exportBytes = contents.toByteArray(Charsets.UTF_8)
                        if (exportBytes!!.size > maxBytes) throw IllegalArgumentException("Backup file is too large.")
                        Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, "Todoniq-backup.json")
                        }
                    } else {
                        Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                        }
                    }
                    pending = result
                    activity.startActivityForResult(intent, requestCode)
                } catch (error: Exception) {
                    pending = null
                    exportBytes = null
                    result.error("backup_file", error.message, null)
                }
            }
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != requestCode) return false
        val result = pending ?: return true
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            pending = null
            exportBytes = null
            result.success(if (exporting) false else null)
            return true
        }
        val save = exporting
        val bytes = exportBytes
        Thread {
            try {
                val output: Any = if (save) {
                    activity.contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                        stream.write(bytes ?: throw IllegalStateException("No backup data."))
                        stream.flush()
                    } ?: throw IllegalStateException("The selected file cannot be written.")
                    true
                } else {
                    activity.contentResolver.openInputStream(uri)?.use { stream ->
                        val buffer = ByteArray(8192)
                        val content = ByteArrayOutputStream()
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            if (content.size() + count > maxBytes) throw IllegalArgumentException("Backup file is too large.")
                            content.write(buffer, 0, count)
                        }
                        Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                            .onUnmappableCharacter(CodingErrorAction.REPORT)
                            .decode(ByteBuffer.wrap(content.toByteArray())).toString()
                    } ?: throw IllegalStateException("The selected file cannot be read.")
                }
                activity.runOnUiThread { finish(result, output, null) }
            } catch (error: Exception) {
                activity.runOnUiThread { finish(result, null, error) }
            }
        }.start()
        return true
    }

    private fun finish(result: MethodChannel.Result, value: Any?, error: Exception?) {
        // Engine destruction may already have completed the pending request.
        if (pending !== result) return
        pending = null
        exportBytes = null
        if (error != null) result.error("backup_file", error.message, null)
        else result.success(value)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.error("backup_cancelled", "The app closed the file picker.", null)
        pending = null
        exportBytes = null
    }
}
