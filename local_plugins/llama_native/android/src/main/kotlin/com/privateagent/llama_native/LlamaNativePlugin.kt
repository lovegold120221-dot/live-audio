package com.privateagent.llama_native

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StringCodec

/** Flutter plugin for on-device LLM inference via llama.cpp. */
class LlamaNativePlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "LlamaNativePlugin"
        private const val CHANNEL = "com.privateagent/llama_native"
        private const val STREAM_CHANNEL = "com.privateagent/llama_native_stream"

        init {
            System.loadLibrary("llama_bridge")
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var streamChannel: BasicMessageChannel<String>
    private var streamThread: Thread? = null

    // JNI native declarations
    private external fun nativeLoadModel(modelPath: String): Boolean
    private external fun nativeIsModelLoaded(): Boolean
    private external fun nativeGetModelInfo(): Map<String, Any>
    private external fun nativeGenerate(prompt: String, maxTokens: Int): String
    private external fun nativeGenerateInit(prompt: String, maxTokens: Int): Boolean
    private external fun nativeGenerateNext(): String
    private external fun nativeGenerateFinish()
    private external fun nativeStopGenerating()
    private external fun nativeUnloadModel()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)

        streamChannel = BasicMessageChannel(
            binding.binaryMessenger,
            STREAM_CHANNEL,
            StringCodec.INSTANCE
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Stop any ongoing generation
        nativeStopGenerating()
        streamThread?.join(2000)
        streamThread = null
        // Clean up model when plugin is detached
        nativeUnloadModel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                if (modelPath == null) {
                    result.error("INVALID_ARGS", "modelPath is required", null)
                    return
                }
                try {
                    val success = nativeLoadModel(modelPath)
                    if (success) {
                        Log.i(TAG, "Model loaded: $modelPath")
                        result.success(true)
                    } else {
                        result.error("LOAD_FAILED", "Failed to load model from: $modelPath", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Load error", e)
                    result.error("LOAD_ERROR", e.message, null)
                }
            }

            "isModelLoaded" -> {
                result.success(nativeIsModelLoaded())
            }

            "getModelInfo" -> {
                result.success(nativeGetModelInfo())
            }

            "generate" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                try {
                    val text = nativeGenerate(prompt, maxTokens)
                    result.success(text)
                } catch (e: Exception) {
                    Log.e(TAG, "Generate error", e)
                    result.error("GENERATE_ERROR", e.message, null)
                }
            }

            "generateStream" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                val maxTokens = call.argument<Int>("maxTokens") ?: 512

                // Kill any previous stream thread
                nativeStopGenerating()
                streamThread?.join(2000)
                streamThread = null

                // Return immediately – streaming happens on a background thread
                result.success(null)

                streamThread = Thread {
                    try {
                        val initialized = nativeGenerateInit(prompt, maxTokens)
                        if (!initialized) {
                            streamChannel.send("[ERROR:Failed to initialize generation]")
                            return@Thread
                        }

                        while (true) {
                            if (Thread.interrupted()) break

                            val token = nativeGenerateNext()
                            if (token.isEmpty()) break
                            streamChannel.send(token)
                        }

                        nativeGenerateFinish()
                        streamChannel.send("[DONE]")
                    } catch (e: Exception) {
                        Log.e(TAG, "Stream error", e)
                        streamChannel.send("[ERROR:${e.message}]")
                        nativeGenerateFinish()
                    }
                }.also {
                    it.isDaemon = true
                    it.start()
                }
            }

            "stopGenerating" -> {
                nativeStopGenerating()
                streamThread?.interrupt()
                result.success(null)
            }

            "unloadModel" -> {
                nativeStopGenerating()
                streamThread?.join(2000)
                streamThread = null
                nativeUnloadModel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}