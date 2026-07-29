import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../phone_server_settings_screen.dart';

class PhoneServerOllamaConfig extends StatefulWidget {
  const PhoneServerOllamaConfig({super.key});

  @override
  State<PhoneServerOllamaConfig> createState() =>
      _PhoneServerOllamaConfigState();
}

class _PhoneServerOllamaConfigState extends State<PhoneServerOllamaConfig> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _modelController;
  late TextEditingController _pathController;
  bool _useTls = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: 'localhost');
    _portController = TextEditingController(text: '11434');
    _modelController = TextEditingController(text: 'llama3.2');
    _pathController = TextEditingController(text: '');
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('ollama_host') ?? 'localhost';
      _portController.text = prefs.getString('ollama_port') ?? '11434';
      _modelController.text = prefs.getString('ollama_model') ?? 'llama3.2';
      _pathController.text = prefs.getString('ollama_path') ?? '';
      _useTls = prefs.getBool('ollama_use_tls') ?? false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ollama_host', _hostController.text);
    await prefs.setString('ollama_port', _portController.text);
    await prefs.setString('ollama_model', _modelController.text);
    await prefs.setString('ollama_path', _pathController.text);
    await prefs.setBool('ollama_use_tls', _useTls);
  }

  void _updateConfig() {
    setState(() {});
    _saveConfig();
    // Trigger parent screen to test connection
    _parentScreenState?._phoneServerSettingsScreenState._testServerConnection();
  }

  _PhoneServerSettingsScreenState? get _parentScreenState {
    // This is tricky to access from nested widget, we'll call through main screen controller
    return null;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _modelController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Host', _hostController, (v) {
            setState(() {});
            _saveConfig();
          }),
          const SizedBox(height: 12),
          _buildTextField('Port', _portController, (v) {
            setState(() {});
            _saveConfig();
          }),
          const SizedBox(height: 16),
          _buildTextField('Model Name', _modelController, (v) {
            setState(() {});
            _saveConfig();
          }),
          const SizedBox(height: 16),
          _buildTextField('Path (optional)', _pathController, (v) {
            setState(() {});
            _saveConfig();
          }),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Use TLS/SSL'),
            value: _useTls,
            onChanged: (bool value) {
              setState(() {
                _useTls = value;
              });
              _saveConfig();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged,
  ) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
