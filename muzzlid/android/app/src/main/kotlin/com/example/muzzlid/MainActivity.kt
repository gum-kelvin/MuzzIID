package com.example.muzzlid

import android.content.Intent
import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var galleryResult: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()
    private var runtime: ModelRuntime? = null
    private var detector: DetectorRuntime? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.muzzlid/gallery").setMethodCallHandler { call, result ->
            if (call.method != "pick") { result.notImplemented() }
            else if (galleryResult != null) { result.error("BUSY", "Gallery already open", null) }
            else {
                galleryResult = result
                try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE) }, 704) }
                catch (e: Exception) { galleryResult = null; result.error("GALLERY", "No image picker available", null) }
            }
        }
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.muzzlid/model").setMethodCallHandler { call, result ->
            if (call.method !in listOf("status", "embed", "detectorStatus", "detect", "detectRgb")) { result.notImplemented(); return@setMethodCallHandler }
            executor.execute {
                try {
                    val model = runtime ?: ModelRuntime(applicationContext).also { runtime = it }
                    val locator = detector ?: DetectorRuntime(applicationContext).also { detector = it }
                    val answer = when (call.method) {
                        "status" -> model.status()
                        "detectorStatus" -> locator.status()
                        "detectRgb" -> locator.detectRgb(call.argument<ByteArray>("rgb") ?: error("Missing RGB"), call.argument<Int>("width") ?: 0, call.argument<Int>("height") ?: 0)
                        "detect" -> locator.detect(call.argument<ByteArray>("jpeg") ?: error("Missing JPEG"))
                        else -> model.embed(call.argument<ByteArray>("jpeg") ?: error("Missing JPEG"))
                    }
                    main.post { result.success(answer) }
                } catch (_: Throwable) {
                    main.post { result.error("MODEL_UNAVAILABLE", "Model could not run. Check the model configuration.", null) }
                }
            }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 704) return
        val result = galleryResult ?: return
        galleryResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(null); return }
        executor.execute {
            try {
                val bytes = contentResolver.openInputStream(data.data!!)?.use { stream -> val buffer = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(8192)
                    while (buffer.size() <= 12000000) {
                        val count = stream.read(chunk)
                        if (count < 0) break
                        buffer.write(chunk, 0, count)
                    }
                    buffer.toByteArray() } ?: error("Cannot read image")
                if (bytes.size > 12000000) error("Image exceeds 12 MB")
                Handler(Looper.getMainLooper()).post { result.success(bytes) }
            } catch (e: Exception) { Handler(Looper.getMainLooper()).post { result.error("IMAGE", "Cannot read image or image exceeds 12 MB", null) } }
        }
    }
    override fun onDestroy() {
        executor.execute { runtime?.close(); detector?.close() }
        executor.shutdown()
        super.onDestroy()
    }
}
