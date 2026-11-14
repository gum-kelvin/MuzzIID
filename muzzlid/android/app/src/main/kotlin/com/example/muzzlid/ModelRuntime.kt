package com.example.muzzlid

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import ai.onnxruntime.*
import org.json.JSONObject
import java.io.File
import java.nio.FloatBuffer
import java.security.MessageDigest

/** Executor-owned model session. Large artifacts are streamed to a private file,
 * never materialized as a Java byte array, then opened by ONNX Runtime by path. */
class ModelRuntime(private val context: Context) : AutoCloseable {
    private var session: OrtSession? = null
    private var config: JSONObject? = null
    private var version = ""
    private var inputSize = 224
    private var dimensions = 512
    private var mean = floatArrayOf(.485f,.456f,.406f)
    private var std = floatArrayOf(.229f,.224f,.225f)
    private val environment = OrtEnvironment.getEnvironment()

    private fun digest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024*1024)
            while (true) { val size = input.read(buffer); if (size < 0) break; hash.update(buffer,0,size) }
        }
        return hash.digest().joinToString("") { "%02x".format(it) }
    }
    private fun load(): Boolean {
        if (session != null) return true
        val names = context.assets.list("models") ?: return false
        if (!names.contains("model.json") || !names.contains("embedder.onnx")) return false
        val metadata = JSONObject(context.assets.open("models/model.json").bufferedReader().use { it.readText() })
        require(metadata.getInt("schema") == 1)
        dimensions = metadata.getInt("dimensions")
        inputSize = metadata.getInt("inputSize")
        require(dimensions in 32..4096 && inputSize in 32..1024)
        fun channels(key: String, fallback: FloatArray): FloatArray {
            val array = metadata.optJSONArray(key) ?: return fallback
            require(array.length() == 3)
            return FloatArray(3) { array.getDouble(it).toFloat() }.also { require(it.all { value -> value.isFinite() }) }
        }
        mean = channels("mean", mean)
        std = channels("std", std)
        require(std.all { it > 0 })
        val hash = metadata.getString("sha256")
        require(hash.matches(Regex("[0-9a-f]{64}")))
        val directory = File(context.noBackupFilesDir,"embedding-models").apply { mkdirs() }
        val modelFile = File(directory,"$hash.onnx")
        if (!modelFile.exists() || digest(modelFile) != hash) {
            val temporary = File(directory,"$hash.tmp")
            context.assets.open("models/embedder.onnx").use { input -> temporary.outputStream().use { input.copyTo(it) } }
            require(digest(temporary) == hash) { "Model checksum mismatch" }
            check(temporary.renameTo(modelFile))
        }
        val next = OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            environment.createSession(modelFile.absolutePath, options)
        }
        try {
            val input = next.inputInfo.values.single().info as TensorInfo
            require(input.type == OnnxJavaType.FLOAT && input.shape.contentEquals(longArrayOf(1,3,inputSize.toLong(),inputSize.toLong())))
            val output = next.outputInfo.values.single().info as TensorInfo
            require(output.type == OnnxJavaType.FLOAT && output.shape.contentEquals(longArrayOf(1,dimensions.toLong())))
            val low = metadata.getDouble("uncertainThreshold")
            val high = metadata.getDouble("matchThreshold")
            require(low >= -1 && high <= 1 && low < high)
            require(metadata.getDouble("minimumMargin") in 0.0..2.0)
            // A preprocessing change must isolate templates even with unchanged weights.
            val contract = "$inputSize:$dimensions:${mean.joinToString()}:${std.joinToString()}"
            val contractHash = MessageDigest.getInstance("SHA-256").digest(contract.toByteArray())
                .joinToString("") { "%02x".format(it) }.take(16)
            version = metadata.getString("version") + ":" + hash + ":" + contractHash
            config = metadata
            session = next
            directory.listFiles()?.filter { it != modelFile && (it.extension == "onnx" || it.extension == "tmp") }?.forEach { it.delete() }
        } catch (error: Throwable) { next.close(); throw error }
        return true
    }

    fun status(): Map<String, Any> {
        if (!load()) return mapOf("ready" to false)
        val metadata = config!!
        return mapOf("ready" to true,"version" to version,"dimensions" to dimensions,"inputSize" to inputSize,
            "modelName" to metadata.optString("displayName",metadata.getString("version")),
            "calibrated" to metadata.getBoolean("calibrated"),"research" to metadata.optBoolean("research",false),
            "matchThreshold" to metadata.getDouble("matchThreshold"),"uncertainThreshold" to metadata.getDouble("uncertainThreshold"),
            "minimumMargin" to metadata.getDouble("minimumMargin"))
    }

    fun embed(bytes: ByteArray): Map<String, Any> {
        check(load()) { "No embedding model installed" }
        require(bytes.size <= 10*1024*1024)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong()*bounds.outHeight <= 16_000_000)
        val source = BitmapFactory.decodeByteArray(bytes,0,bytes.size) ?: error("Invalid JPEG")
        val scaled = Bitmap.createScaledBitmap(source,inputSize,inputSize,true)
        val values = FloatArray(3*inputSize*inputSize)
        try {
            val pixels = IntArray(inputSize*inputSize)
            scaled.getPixels(pixels,0,inputSize,0,0,inputSize,inputSize)
            for (i in pixels.indices) for (c in 0..2) {
                val channel = (pixels[i] shr (16-c*8)) and 255
                values[c*pixels.size+i] = (channel/255f-mean[c])/std[c]
            }
        } finally { if (scaled !== source) scaled.recycle(); source.recycle() }
        OnnxTensor.createTensor(environment,FloatBuffer.wrap(values),longArrayOf(1,3,inputSize.toLong(),inputSize.toLong())).use { input ->
            session!!.run(mapOf(session!!.inputNames.single() to input)).use { output ->
                val vector = (output[0].value as Array<*>).single() as FloatArray
                require(vector.size == dimensions && vector.all { it.isFinite() })
                val length = kotlin.math.sqrt(vector.sumOf { it.toDouble()*it })
                require(length > 1e-12)
                return mapOf("version" to version,"dimensions" to dimensions,"vector" to vector.map { it/length })
            }
        }
    }
    override fun close() { session?.close(); session = null }
}
