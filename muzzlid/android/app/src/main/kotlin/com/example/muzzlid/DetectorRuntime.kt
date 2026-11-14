package com.example.muzzlid

import android.content.Context
import android.graphics.*
import ai.onnxruntime.*
import org.json.JSONObject
import java.nio.FloatBuffer
import java.security.MessageDigest

/** Single-class YOLOv8 raw output, letterboxed RGB input. Executor-owned. */
class DetectorRuntime(private val context: Context) : AutoCloseable {
    private var session: OrtSession? = null
    private val environment = OrtEnvironment.getEnvironment()
    private var threshold = .5f
    fun status(): Map<String, Any> {
        if (session != null) return mapOf("ready" to true)
        val names = context.assets.list("models") ?: return mapOf("ready" to false)
        if (!names.contains("detector.onnx") || !names.contains("detector.json")) return mapOf("ready" to false)
        val config = JSONObject(context.assets.open("models/detector.json").bufferedReader().use { it.readText() })
        require(config.getInt("schema") == 1 && config.getInt("inputSize") == 640)
        val bytes = context.assets.open("models/detector.onnx").use { it.readBytes() }
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        require(hash == config.getString("sha256"))
        threshold = config.getDouble("confidenceThreshold").toFloat()
        require(threshold.isFinite() && threshold > 0f && threshold <= 1f)
        val next = OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            environment.createSession(bytes, options)
        }
        try {
            val input = next.inputInfo.values.single().info as TensorInfo
            val output = next.outputInfo.values.single().info as TensorInfo
            require(input.type == OnnxJavaType.FLOAT && input.shape.contentEquals(longArrayOf(1,3,640,640)))
            require(output.type == OnnxJavaType.FLOAT && output.shape.size == 3 && output.shape[0] == 1L && output.shape[1] == 5L && output.shape[2] > 0)
            session = next
        } catch (error: Throwable) { next.close(); throw error }
        return mapOf("ready" to true)
    }
    fun detect(bytes: ByteArray): Map<String, Any> {
        check(status()["ready"] == true)
        require(bytes.size <= 10 * 1024 * 1024)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 16_000_000)
        val image = BitmapFactory.decodeByteArray(bytes,0,bytes.size) ?: error("Invalid JPEG")
        return detectImage(image)
    }
    fun detectRgb(bytes: ByteArray, width: Int, height: Int): Map<String, Any> {
        check(status()["ready"] == true)
        require(width > 0 && height > 0 && width.toLong()*height <= 1_000_000 && bytes.size.toLong() == width.toLong()*height*3)
        val pixels = IntArray(width*height) { i ->
            (255 shl 24) or ((bytes[i*3].toInt() and 255) shl 16) or ((bytes[i*3+1].toInt() and 255) shl 8) or (bytes[i*3+2].toInt() and 255)
        }
        return detectImage(Bitmap.createBitmap(pixels,width,height,Bitmap.Config.ARGB_8888))
    }
    private fun detectImage(image: Bitmap): Map<String, Any> {
        val canvasImage = Bitmap.createBitmap(640,640,Bitmap.Config.ARGB_8888)
        val scale = minOf(640f/image.width,640f/image.height)
        val dx = (640-image.width*scale)/2
        val dy = (640-image.height*scale)/2
        val width = image.width.toFloat()
        val height = image.height.toFloat()
        val values = FloatArray(3*640*640)
        try {
            val canvas = Canvas(canvasImage)
            canvas.drawColor(Color.rgb(114,114,114))
            canvas.drawBitmap(image,null,RectF(dx,dy,dx+width*scale,dy+height*scale),Paint(Paint.FILTER_BITMAP_FLAG))
            val pixels = IntArray(640*640)
            canvasImage.getPixels(pixels,0,640,0,0,640,640)
            for (i in pixels.indices) for (c in 0..2) values[c*pixels.size+i] = ((pixels[i] shr (16-c*8)) and 255)/255f
        } finally { image.recycle(); canvasImage.recycle() }
        OnnxTensor.createTensor(environment,FloatBuffer.wrap(values),longArrayOf(1,3,640,640)).use { input ->
            session!!.run(mapOf(session!!.inputNames.single() to input)).use { output ->
                val channels = (output[0].value as Array<*>).single() as Array<*>
                val rows = channels.map { it as FloatArray }
                var best = -1
                for (i in rows[4].indices) if (rows.all { it[i].isFinite() } && rows[4][i] >= threshold && (best < 0 || rows[4][i] > rows[4][best])) best = i
                if (best < 0) return mapOf("found" to false)
                val x = (rows[0][best]-rows[2][best]/2-dx)/scale/width
                val y = (rows[1][best]-rows[3][best]/2-dy)/scale/height
                val w = rows[2][best]/scale/width
                val h = rows[3][best]/scale/height
                if (!x.isFinite() || !y.isFinite() || !w.isFinite() || !h.isFinite() || w <= 0 || h <= 0 || w > 2 || h > 2 || x !in -1f..2f || y !in -1f..2f) return mapOf("found" to false)
                return mapOf("found" to true, "x" to x.toDouble(), "y" to y.toDouble(), "width" to w.toDouble(), "height" to h.toDouble())
            }
        }
    }
    override fun close() { session?.close(); session = null }
}
