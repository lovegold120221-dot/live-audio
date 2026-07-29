import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/agent_action.dart';

/// A service that connects to Google's Gemini Live Audio API via WebSocket.
///
/// The Gemini Live API provides a single real-time bidirectional audio stream
/// where the user speaks naturally and the model responds with both audio (played
/// aloud) and text (for parsing device actions). This replaces the traditional
/// STT → LLM → TTS pipeline with one continuous interaction.
///
/// ## Usage
/// ```dart
/// final service = GeminiLiveAudioService();
///
/// // One-shot interaction (recommended for task-driven agents)
/// final result = await service.interact("Open WhatsApp and tell John I'm late");
/// if (result.action != null) {
///   // execute device action...
/// }
/// ```
class GeminiLiveAudioService {
  static const String _defaultBaseUrl =
      'https://generativelanguage.googleapis.com';
  static const String _wsPath =
      '/ws/google.ai.v1.GeminiService.StreamingGenerateContent';

  String? _apiKey;
  String _model = 'models/gemini-2.0-flash-exp';
  WebSocket? _ws;
  bool _isConnecting = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // Streams for UI consumers
  final StreamController<String> _responseStreamController =
      StreamController<String>.broadcast();
  final StreamController<AgentAction?> _actionStreamController =
      StreamController<AgentAction?>.broadcast();
  final StreamController<String> _statusStreamController =
      StreamController<String>.broadcast();

  bool get isConnected => _ws != null && !_ws!.readyState.toString().contains('closed');
  bool get isConnecting => _isConnecting;

  Stream<String> get responseStream => _responseStreamController.stream;
  Stream<AgentAction?> get actionStream => _actionStreamController.stream;
  Stream<String> get statusStream => _statusStreamController.stream;

  /// Connect to the Gemini Live API via WebSocket.
  Future<void> connect({String? apiKey}) async {
    if (isConnected) return;
    if (_isConnecting) return;

    final key = apiKey ??= await _loadApiKey();
    if (key == null || key.isEmpty) {
      throw Exception('Gemini API key not configured.');
    }

    _apiKey = key;
    _isConnecting = true;
    _retryCount = 0;

    await _connectWithRetry(key);
  }

  Future<void> _connectWithRetry(String apiKey) async {
    while (_retryCount < _maxRetries) {
      try {
        _statusStreamController.add('Connecting...');

        final uri = Uri.parse(
          'wss://generativelanguage.googleapis.com'
          '$_wsPath?key=$apiKey',
        );

        _ws = await WebSocket.connect(
          uri.toString(),
          headers: {
            'x-go-api-key': apiKey,
          },
        );

        _isConnecting = false;
        _retryCount = 0;
        _statusStreamController.add('Connected');
        developer.log('Gemini Live connected', name: 'GeminiLiveAudio');

        _setupHandlers();
        await _sendSetup();
        return;
      } catch (e) {
        _retryCount++;
        _statusStreamController.add('Reconnecting... ($_retryCount/$_maxRetries)');
        developer.log(
          'Gemini Live connect attempt $_retryCount failed: $e',
          name: 'GeminiLiveAudio',
        );
        await Future.delayed(_retryDelay);
      }
    }

    throw Exception(
      'Failed to connect to Gemini Live API after $_maxRetries attempts.',
    );
  }

  /// Send the initial setup configuration.
  Future<void> _sendSetup() async {
    final setup = {
      'setup': {
        'model': _model,
        'generation_config': {
          'response_modalities': ['AUDIO'],
        },
        'system_instruction': {
          'parts': [
            {'text': _buildSystemPrompt()},
          ],
        },
      },
    };
    await _ws!.add(jsonEncode(setup));
    developer.log('Sent Gemini setup config', name: 'GeminiLiveAudio');
  }

  String _buildSystemPrompt() {
    return '''
You are Eburon OS, an AI agent that controls an Android phone. You can perform device actions and also have normal conversations.

When the user wants you to perform a device action, respond with a JSON object (no markdown, no code fences, no extra text) in this exact format:
{"action": "action_name", "params": {"key": "value"}, "response": "What you say to the user"}

Available actions and their params:

SIMPLE ACTIONS (single step only):
- open_app: {"app_name": "YouTube"} - ONLY use when the user JUST wants to open an app and nothing else
- make_call: {"contact_name": "Mom"} OR {"phone_number": "1234567890"} - Makes a phone call
- send_sms: {"contact_name": "John", "message": "Hello"} OR {"phone_number": "123", "message": "Hi"} - Sends SMS
- search_contact: {"query": "John"} - Searches contacts
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"} - Sets an alarm
- set_volume: {"level": 50} - Sets volume (0-100)
- set_brightness: {"level": 50} - Sets brightness (0-100)
- read_screen: {} - Read what's currently on the screen
- press_back: {} - Press the back button

MULTI-STEP TASK (for anything that requires more than one action):
- execute_task: {"goal": "description of the full task"} - Automatically reads screen, taps, scrolls, types step by step

CRITICAL RULES:
1. If the user request involves MULTIPLE steps (open + search, open + send, etc.), you MUST use execute_task. NEVER use open_app for multi-step requests.
2. execute_task handles everything: opening apps, finding elements, clicking, typing, scrolling.

For normal conversation (questions, chat, info requests), just respond naturally with plain text — no JSON needed.

IMPORTANT: When sending a JSON action, keep it on ONE LINE so it can be parsed reliably.
''';
  }

  /// Set up the WebSocket message handler.
  void _setupHandlers() {
    _ws!.listen(
      (data) {
        if (data is String) {
          _handleTextMessage(data);
        } else if (data is List<int> || data is Uint8List) {
          // Binary audio frame — decode and handle as text
          final text = utf8.decode(data as List<int>);
          _handleTextMessage(text);
        }
      },
      onError: (error) {
        developer.log('Gemini Live error: $error', name: 'GeminiLiveAudio');
        _statusStreamController.add('Error: $error');
      },
      onDone: () {
        developer.log('Gemini Live connection closed', name: 'GeminiLiveAudio');
        _isConnecting = false;
        _statusStreamController.add('Disconnected');
      },
    );
  }

  /// Handle an incoming JSON message from Gemini.
  Future<void> _handleTextMessage(String raw) async {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;

      // Single-turn model response (audio + text)
      if (json.containsKey('model_content')) {
        final content = json['model_content'] as Map<String, dynamic>;
        final textParts = <String>[];

        if (content['candidates'] is List) {
          for (final candidate in content['candidates'] as List) {
            if (candidate is Map &&
                candidate['content'] is Map &&
                candidate['content']['parts'] is List) {
              for (final part in candidate['content']['parts'] as List) {
                if (part is Map && part['text'] != null) {
                  textParts.add(part['text'] as String);
                }
              }
            }
          }
        }

        final text = textParts.join('\n');
        if (text.isNotEmpty) {
          await _responseStreamController.addStream(Stream.value(text));
          developer.log(
            'Gemini response: $text',
            name: 'GeminiLiveAudio',
          );
        }
        return;
      }

      // Tool request — Gemini wants to use a tool
      if (json.containsKey('tool_request')) {
        developer.log(
          'Tool request from Gemini: ${json['tool_request']}',
          name: 'GeminiLiveAudio',
        );
        // TODO: Implement tool execution logic
        // For now, send an empty tool response to continue the flow
        // (The agent will handle the task via execute_task action instead)
        return;
      }

      // Server content (turn complete marker or other signals)
      if (json.containsKey('server_content')) {
        // Could add handling for turn completion markers
        return;
      }

      // Setup complete
      if (json.containsKey('setup_complete')) {
        _statusStreamController.add('Ready');
        developer.log('Gemini setup complete', name: 'GeminiLiveAudio');
        return;
      }
    } catch (e) {
      developer.log('Failed to parse Gemini message: $e', name: 'GeminiLiveAudio');
    }
  }

  /// Send text to Gemini. Automatically connects if needed.
  Future<void> sendText(String text) async {
    if (!isConnected) {
      await connect();
    }

    final message = {
      'client_content': {
        'turns': [
          {'text': text},
        ],
        'turn_type': 1, // SINGLE_TURN
      },
    };

    await _ws!.add(jsonEncode(message));
  }

  /// Send raw audio bytes to Gemini. Automatically connects if needed.
  Future<void> sendAudio(List<int> audioBytes) async {
    if (!isConnected) {
      await connect();
    }
    await _ws!.add(audioBytes);
  }

  /// Disconnect from Gemini Live API.
  Future<void> disconnect() async {
    try {
      await _ws?.close(1000, 'Client closing');
    } catch (_) {}
    _ws = null;
    _isConnecting = false;
    _statusStreamController.add('Disconnected');
  }

  /// One-shot interaction: send text, collect full response.
  /// Returns (text, action). The [action] is parsed from the response text.
  Future<(String text, AgentAction? action)> interact(String input) async {
    if (!isConnected) {
      await connect();
    }

    final completer = Completer<String>();
    String finalText = '';

    final subscription = responseStream.listen(
      (chunk) {
        finalText += chunk;
        if (!completer.isCompleted) {
          completer.complete(finalText);
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted && finalText.isNotEmpty) {
          completer.complete(finalText);
        }
      },
    );

    await sendText(input);

    try {
      finalText = await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => 'Request timed out after 2 minutes.',
      );
    } catch (e) {
      developer.log('Interact timed out or errored: $e', name: 'GeminiLiveAudio');
      rethrow;
    } finally {
      await subscription.cancel();
    }

    // Parse the response for an action
    final action = _parseAction(finalText);

    return (finalText, action);
  }

  /// Parse a JSON action from free-text Gemini response.
  static AgentAction? _parseAction(String text) {
    try {
      final trimmed = text.trim();
      String jsonStr = trimmed;

      // Handle markdown code fences
      if (trimmed.startsWith('\`\`\`')) {
        final lines = trimmed.split('\n');
        lines.removeAt(0);
        if (lines.isNotEmpty && lines.last.trim() == '\`\`\`') {
          lines.removeLast();
        }
        jsonStr = lines.join('\n').trim();
      }

      // Find first { and last }
      final startIdx = jsonStr.indexOf('{');
      final endIdx = jsonStr.lastIndexOf('}');
      if (startIdx >= 0 && endIdx > startIdx) {
        jsonStr = jsonStr.substring(startIdx, endIdx + 1);
      }

      if (!jsonStr.startsWith('{') || !jsonStr.contains('"action"')) {
        return null;
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json.containsKey('action')) {
        return AgentAction.fromJson(json as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Stream all interactions. Each user message yields a response stream.
  Stream<(String text, AgentAction? action)> interactStream() async* {
    while (isConnected) {
      yield* _responseStreamController.stream.map(
        (text) => (text, _parseAction(text)),
      );
    }
  }

  /// Save API key to SharedPreferences.
  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_live_api_key', key);
  }

  /// Load API key from SharedPreferences.
  Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('gemini_live_api_key');
  }

  /// Dispose all controllers and close the connection.
  void dispose() {
    disconnect();
    _responseStreamController.close();
    _actionStreamController.close();
    _statusStreamController.close();
  }
}
