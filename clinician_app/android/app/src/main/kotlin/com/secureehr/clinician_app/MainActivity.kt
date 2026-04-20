package com.secureehr.clinician_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val documentChannel = "secureehr/clinician_documents"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, documentChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDocumentBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "patient_record.pdf"

                        if (bytes == null) {
                            result.error("missing_bytes", "No document bytes were provided.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            openDocument(bytes, fileName)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("open_document_failed", error.message, null)
                        }
                    }

                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("missing_url", "No external URL was provided.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            openExternalUrl(url)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("open_url_failed", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun openDocument(bytes: ByteArray, fileName: String) {
        val safeName = fileName
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "patient_record.pdf" }

        val directory = File(cacheDir, "shared_documents").apply {
            if (!exists()) {
                mkdirs()
            }
        }

        val file = File(directory, safeName)
        file.writeBytes(bytes)

        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val extension = file.extension.lowercase()
        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/pdf"

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            startActivity(Intent.createChooser(intent, "Open document"))
        } catch (_: ActivityNotFoundException) {
            throw IllegalStateException("No app is available to open this document.")
        }
    }

    private fun openExternalUrl(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            throw IllegalStateException("No app is available to open this link.")
        }
    }
}
