package com.example.muzzlid

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var runtime: ModelRuntime? = null
    private var detector: DetectorRuntime? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
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
    override fun onDestroy() {
        executor.execute { runtime?.close(); detector?.close() }
        executor.shutdown()
        super.onDestroy()
    }
}
