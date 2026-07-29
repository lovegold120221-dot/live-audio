import 'dart:async';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llama_native/llama_native.dart';

/// High-level service for on-device LLM inference via GGUF models.
///
/// Handles prompt formatting (chat template), conversation history, model
/// lifecycle, and provides the same interface as [AiService] so the rest of
/// the app can treat local and remote models uniformly.
class LocalInferenceService {
  final LlamaNative _llama = LlamaNative();

  bool _modelLoaded = false;
  String? _modelPath;
  int _maxTokens = 512;
  int _contextSize = 2048;

  // Conversation history (maps to the native context window)
  final List<Map<String, String>> _conversationHistory = [];

  /// Whether a model is currently loaded and ready for inference.
  bool get isModelLoaded => _modelLoaded;

  /// Path to the currently loaded model (or null if none).
  String? get modelPath => _modelPath;

  // ---- Settings persistence ------------------------------------------------

  /// Load settings from [SharedPreferences].
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _maxTokens = prefs.getInt('local_max_tokens') ?? 512;
    final savedPath = prefs.getString('local_model_path');
    if (savedPath != null && savedPath.isNotEmpty) {
      _modelPath = savedPath;
    }
  }

  /// Persist model path.
  Future<void> saveModelPath(String path) async {
    _modelPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_model_path', path);
  }

  /// Persist max tokens setting.
  Future<void> saveMaxTokens(int tokens) async {
    _maxTokens = tokens;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_max_tokens', tokens);
  }

  // ---- Model lifecycle ----------------------------------------------------

  /// Load a GGUF model from [path].
  /// Returns true on success.
  Future<bool> loadModel(String path) async {
    try {
      final success = await _llama.loadModel(path);
      if (success) {
        _modelLoaded = true;
        _modelPath = path;
        await saveModelPath(path);
        developer.log('Local model loaded: $path', name: 'LocalInference');

        // Query model info
        try {
          final info = await _llama.getModelInfo();
          _contextSize = (info['contextSize'] as int?) ?? 2048;
          developer.log(
            'Model info: context=$_contextSize, vocab=${info['vocabularySize']}',
            name: 'LocalInference',
          );
        } catch (_) {}

        _conversationHistory.clear();
      }
      return success;
    } catch (e) {
      developer.log('Failed to load local model: $e', name: 'LocalInference');
      _modelLoaded = false;
      return false;
    }
  }

  /// Unload the model and free memory.
  Future<void> unloadModel() async {
    try {
      await _llama.unloadModel();
    } catch (_) {}
    _modelLoaded = false;
    _modelPath = null;
    _conversationHistory.clear();
    developer.log('Local model unloaded', name: 'LocalInference');
  }

  /// Stop any ongoing generation.
  Future<void> stopGenerating() async {
    await _llama.stopGenerating();
  }

  // ---- Chat interface -----------------------------------------------------

  /// Format the conversation for the model.
  /// Uses a ChatML-like template (works with most instruct-tuned models).
  String _formatPrompt(String userMessage) {
    final buffer = StringBuffer();

    // System prompt
    buffer.writeln('<|im_start|>system');
    buffer.writeln(
      'You are Eburon OS, a helpful AI assistant running locally on-device. '
      'Answer questions concisely and helpfully.',
    );
    buffer.writeln('<|im_end|>');

    // Conversation history
    for (final msg in _conversationHistory) {
      final role = msg['role'] == 'user' ? 'user' : 'assistant';
      buffer.writeln('<|im_start|>$role');
      buffer.writeln(msg['content']);
      buffer.writeln('<|im_end|>');
    }

    // Current user message
    buffer.writeln('<|im_start|>user');
    buffer.writeln(userMessage);
    buffer.writeln('<|im_end|>');
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  /// Send a message and return the full response (non-streaming).
  Future<String> sendMessage(String message) async {
    if (!_modelLoaded) {
      throw Exception('Local model is not loaded. Load a GGUF model first.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 10);
    }

    final prompt = _formatPrompt(message);
    developer.log(
      'Local inference prompt length: ${prompt.length}',
      name: 'LocalInference',
    );

    try {
      final response = await _llama.generate(prompt, maxTokens: _maxTokens);
      final trimmed = response.trim();

      _conversationHistory.add({'role': 'assistant', 'content': trimmed});
      if (_conversationHistory.length > 10) {
        _conversationHistory.removeRange(0, _conversationHistory.length - 10);
      }

      return trimmed;
    } catch (e) {
      developer.log('Local inference error: $e', name: 'LocalInference');
      rethrow;
    }
  }

  /// Send a message and stream the response token-by-token.
  Stream<String> sendMessageStream(String message) async* {
    if (!_modelLoaded) {
      throw Exception('Local model is not loaded. Load a GGUF model first.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 10);
    }

    final prompt = _formatPrompt(message);
    developer.log(
      'Local stream prompt length: ${prompt.length}',
      name: 'LocalInference',
    );

    try {
      final accumulated = StringBuffer();

      await for (final token in _llama.generateStream(
        prompt,
        maxTokens: _maxTokens,
      )) {
        accumulated.write(token);
        yield token;
      }

      final finalText = accumulated.toString().trim();
      _conversationHistory.add({'role': 'assistant', 'content': finalText});
      if (_conversationHistory.length > 10) {
        _conversationHistory.removeRange(0, _conversationHistory.length - 10);
      }
    } catch (e) {
      developer.log('Local stream error: $e', name: 'LocalInference');
      rethrow;
    }
  }

  /// Clear conversation history.
  void clearHistory() {
    _conversationHistory.clear();
  }

  /// Get model metadata.
  Future<Map<String, dynamic>> getModelInfo() async {
    return _llama.getModelInfo();
  }

  // ---- Settings accessors -------------------------------------------------

  int get maxTokens => _maxTokens;
  int get contextSize => _contextSize;
}
