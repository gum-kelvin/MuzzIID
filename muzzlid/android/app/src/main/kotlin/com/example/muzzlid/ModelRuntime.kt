package com.example.muzzlid

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import ai.onnxruntime.*
import org.json.JSONObject
import java.nio.FloatBuffer
import java.security.MessageDigest

/** Owned by one executor; no tensors, model bytes or inference run on the UI thread. */
class ModelRuntime(private val context: Context) : AutoCloseable {
    private var session: OrtSession? = null
    private var config: JSONObject? = null
    private var version = ""
    private val environment = OrtEnvironment.getEnvironment()

    private fun load(): Boolean {
        if (session != null) return true
        val names = context.assets.list("models") ?: return false
        if (!names.contains("model.json") || !names.contains("embedder.onnx")) return false
        val metadata = JSONObject(context.assets.open("models/model.json").bufferedReader().use { it.readText() })
        require(metadata.getInt("schema") == 1)
        require(metadata.getInt("dimensions") == 512)
        require(metadata.getInt("inputSize") == 224)
        val bytes = context.assets.open("models/embedder.onnx").use { it.readBytes() }
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        require(hash == metadata.getString("sha256")) { "Model checksum mismatch" }
        val next = OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            environment.createSession(bytes, options)
        }
        try {
            val input = next.inputInfo.values.single().info as TensorInfo
            require(input.type == OnnxJavaType.FLOAT && input.shape.contentEquals(longArrayOf(1, 3, 224, 224)))
            val output = next.outputInfo.values.single().info as TensorInfo
            require(output.type == OnnxJavaType.FLOAT && output.shape.contentEquals(longArrayOf(1, 512)))
            val low = metadata.getDouble("uncertainThreshold")
            val high = metadata.getDouble("matchThreshold")
            require(low >= -1 && high <= 1 && low < high)
            require(metadata.getDouble("minimumMargin") in 0.0..2.0)
            version = metadata.getString("version") + ":" + hash
            config = metadata
            session = next
        } catch (error: Throwable) { next.close(); throw error }
        return true
    }

    fun status(): Map<String, Any> {
        if (!load()) return mapOf("ready" to false)
        val metadata = config!!
        return mapOf("ready" to true, "version" to version,
            "calibrated" to metadata.getBoolean("calibrated"),
            "research" to metadata.optBoolean("research", false),
            "matchThreshold" to metadata.getDouble("matchThreshold"),
            "uncertainThreshold" to metadata.getDouble("uncertainThreshold"),
            "minimumMargin" to metadata.getDouble("minimumMargin"))
    }

    fun embed(bytes: ByteArray): Map<String, Any> {
        check(load()) { "No embedding model installed" }
        require(bytes.size <= 10 * 1024 * 1024)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 16_000_000)
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: error("Invalid JPEG")
        val scaled = Bitmap.createScaledBitmap(source, 224, 224, true)
        val values = FloatArray(3 * 224 * 224)
        val mean = floatArrayOf(.485f, .456f, .406f)
        val std = floatArrayOf(.229f, .224f, .225f)
        try {
            val pixels = IntArray(224 * 224)
            scaled.getPixels(pixels, 0, 224, 0, 0, 224, 224)
            for (i in pixels.indices) for (c in 0..2) {
                val channel = (pixels[i] shr (16 - c * 8)) and 255
                values[c * pixels.size + i] = (channel / 255f - mean[c]) / std[c]
            }
        } finally {
            if (scaled !== source) scaled.recycle()
            source.recycle()
        }
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(values), longArrayOf(1, 3, 224, 224)).use { input ->
            session!!.run(mapOf(session!!.inputNames.single() to input)).use { output ->
                val vector = (output[0].value as Array<*>).single() as FloatArray
                require(vector.size == 512 && vector.all { it.isFinite() })
                val length = kotlin.math.sqrt(vector.sumOf { it.toDouble() * it })
                require(length > 1e-12)
                return mapOf("version" to version, "vector" to vector.map { it / length })
            }
        }
    }
    override fun close() { session?.close(); session = null }
}
