import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/ai_service.dart';
import 'phone_server_config/phone_server_ollama_config.dart';
import 'phone_server_config/phone_server_ollama_cloud_config.dart';
import 'phone_server_config/phone_server_gemini_config.dart';
import 'phone_server_config/phone_server_groq_config.dart';
import 'phone_server_config/phone_server_opencode_config.dart';
import '../config/feature_flags.dart';

class PhoneServerSettingsScreen extends StatefulWidget {
  const PhoneServerSettingsScreen({super.key});

  @override
  State<PhoneServerSettingsScreen> createState() =>
      _PhoneServerSettingsScreenState();
}

class _PhoneServerSettingsScreenState extends State<PhoneServerSettingsScreen> {
  String _selectedServer = 'ollama';
  bool _isServerConnected = false;
  String _serverStatus = 'Disconnected';
  Map<String, dynamic> _serverConfig = {};
  String _connectionError = '';

  @override
  void initState() {
    super.initState();
    _loadServerConfig();
    _testServerConnection();
  }

  Future<void> _loadServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedServer = prefs.getString('selected_server') ?? 'ollama';
      _serverConfig = {
        'host': prefs.getString('server_host') ?? 'localhost',
        'port': prefs.getInt('server_port') ?? 4096,
        'protocol': prefs.getString('server_protocol') ?? 'http',
        'path': prefs.getString('server_path') ?? '',
        'auth_token': prefs.getString('server_auth_token') ?? '',
        'username': prefs.getString('server_username') ?? '',
        'password': prefs.getString('server_password') ?? '',
        'use_tls': prefs.getBool('server_use_tls') ?? false,
        'timeout': prefs.getInt('server_timeout') ?? 30000,
      };
    });
  }

  Future<void> _testServerConnection() async {
    setState(() {
      _serverStatus = 'Testing...';
      _isServerConnected = false;
      _connectionError = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('server_host') ?? 'localhost';
      final port = prefs.getInt('server_port') ?? 4096;
      final protocol = prefs.getString('server_protocol') ?? 'http';

      // Test basic connectivity
      final timeout = Duration(
        milliseconds: prefs.getInt('server_timeout') ?? 30000,
      );

      // Try to establish a socket connection to test server availability
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.close();

      if (mounted) {
        setState(() {
          _serverStatus = 'Connected';
          _isServerConnected = true;
          _connectionError = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serverStatus = 'Disconnected';
          _isServerConnected = false;
          _connectionError = 'Connection failed: \${e.toString()}';
        });
      }
    }
  }

  void _saveServerConfig() {
    final prefs = SharedPreferences.getInstance();
    prefs.then((prefs) {
      prefs.setString('selected_server', _selectedServer);
      prefs.setString('server_host', _serverConfig['host'] as String);
      prefs.setInt('server_port', _serverConfig['port'] as int);
      prefs.setString('server_protocol', _serverConfig['protocol'] as String);
      prefs.setString('server_path', _serverConfig['path'] as String);
      prefs.setString(
        'server_auth_token',
        _serverConfig['auth_token'] as String,
      );
      prefs.setString('server_username', _serverConfig['username'] as String);
      prefs.setString('server_password', _serverConfig['password'] as String);
      prefs.setBool('server_use_tls', _serverConfig['use_tls'] as bool);
      prefs.setInt('server_timeout', _serverConfig['timeout'] as int);
    });
  }

  void _updateServerConfig(String key, dynamic value) {
    setState(() {
      _serverConfig[key] = value;
    });
    _saveServerConfig();
    _testServerConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Server Settings'),
        backgroundColor: const Color(0xFF4F46E5),
      ),
      body: Column(
        children: [
          _buildServerStatusCard(),
          _buildServerSelector(),
          Expanded(child: _buildServerConfigPanel()),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isServerConnected ? Icons.check_circle : Icons.error,
              color: _isServerConnected ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Server Status: $_serverStatus',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_connectionError.isNotEmpty)
                    Text(
                      _connectionError,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: _testServerConnection,
              icon: const Icon(Icons.refresh),
              tooltip: 'Test Connection',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerSelector() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Server Provider',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildServerOptionButton(
                    'Ollama',
                    'ollama',
                    Icons.computer,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildServerOptionButton(
                    'Ollama Cloud',
                    'ollama_cloud',
                    Icons.cloud,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildServerOptionButton(
                    'Gemini',
                    'gemini',
                    Icons.psychology,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildServerOptionButton(
                    'Groq',
                    'groq',
                    Icons.speed,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildServerOptionButton(
                    'Opencode CLI',
                    'opencode',
                    Icons.terminal,
                    Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerOptionButton(
    String name,
    String value,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedServer == value;
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? color.withValues(alpha: 0.1) : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedServer = value;
            _saveServerConfig();
            _testServerConnection();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, size: 32, color: isSelected ? color : Colors.grey),
              const SizedBox(height: 8),
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? color : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerConfigPanel() {
    switch (_selectedServer) {
      case 'ollama':
        return const PhoneServerOllamaConfig();
      case 'ollama_cloud':
        return const PhoneServerOllamaCloudConfig();
      case 'gemini':
        return const PhoneServerGeminiConfig();
      case 'groq':
        return const PhoneServerGroqConfig();
      case 'opencode':
        return const PhoneServerOpencodeConfig();
      default:
        return const Center(
          child: Text('No configuration available for selected server'),
        );
    }
  }
}
