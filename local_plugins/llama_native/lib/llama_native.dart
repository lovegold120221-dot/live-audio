import 'dart:async';
import 'package:flutter/services.dart';

/// Low-level Dart API for on-device LLM inference via llama.cpp.
class LlamaNative {
  static const MethodChannel _channel = MethodChannel(
    'com.privateagent/llama_native',
  );

  static const BasicMessageChannel<String> _streamChannel =
      BasicMessageChannel<String>(
        'com.privateagent/llama_native_stream',
        StringCodec(),
      );

  /// Load a GGUF model from [modelPath].
  /// Returns true on success, throws on failure.
  Future<bool> loadModel(String modelPath) async {
    final result = await _channel.invokeMethod<bool>('loadModel', {
      'modelPath': modelPath,
    });
    return result ?? false;
  }

  /// Check whether a model is currently loaded in memory.
  Future<bool> isModelLoaded() async {
    final result = await _channel.invokeMethod<bool>('isModelLoaded');
    return result ?? false;
  }

  /// Get metadata about the loaded model (context size, etc.).
  Future<Map<String, dynamic>> getModelInfo() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getModelInfo',
    );
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Generate a completion for the given [prompt].
  /// Returns the full generated text.
  Future<String> generate(String prompt, {int maxTokens = 512}) async {
    final result = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
    });
    return result ?? '';
  }

  /// Generate a streaming completion.
  /// Yields only text tokens — control messages ([DONE], [ERROR:...]) are
  /// filtered out internally and the stream closes cleanly on completion.
  Stream<String> generateStream(String prompt, {int maxTokens = 512}) {
    final controller = StreamController<String>();

    // Set up a handler to receive tokens from the platform side
    _streamChannel.setMessageHandler((message) async {
      if (message == null) {
        unawaited(controller.close());
        return '';
      }
      if (message == '[DONE]') {
        unawaited(controller.close());
      } else if (message.startsWith('[ERROR:')) {
        controller.addError(
          Exception(message.substring(7, message.length - 1)),
        );
        unawaited(controller.close());
      } else {
        controller.add(message);
      }
      return '';
    });

    // Clean up the handler when the stream is done or cancelled
    controller.onCancel = () {
      _streamChannel.setMessageHandler(null);
    };
    controller.done.then((_) {
      _streamChannel.setMessageHandler(null);
    });

    // Start generation (returns immediately, runs on background thread)
    _channel.invokeMethod('generateStream', {
      'prompt': prompt,
      'maxTokens': maxTokens,
    });

    return controller.stream;
  }

  /// Stop any ongoing generation immediately.
  Future<void> stopGenerating() async {
    await _channel.invokeMethod<void>('stopGenerating');
  }

  /// Unload the model and free memory.
  Future<void> unloadModel() async {
    await _channel.invokeMethod<void>('unloadModel');
  }
}
