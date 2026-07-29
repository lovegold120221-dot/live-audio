import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../phone_server_settings_screen.dart';

class PhoneServerOllamaCloudConfig extends StatefulWidget {
  const PhoneServerOllamaCloudConfig({super.key});

  @override
  State<PhoneServerOllamaCloudConfig> createState() =>
      _PhoneServerOllamaCloudConfigState();
}

class _PhoneServerOllamaCloudConfigState
    extends State<PhoneServerOllamaCloudConfig> {
  late TextEditingController _apiKeyController;
  late TextEditingController _endpointController;
  late TextEditingController _organizationController;
  bool _isCustomEndpoint = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _endpointController = TextEditingController(text: 'https://api.ollama.ai');
    _organizationController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('ollama_cloud_api_key') ?? '';
      _endpointController.text =
          prefs.getString('ollama_cloud_endpoint') ?? 'https://api.ollama.ai';
      _organizationController.text =
          prefs.getString('ollama_cloud_organization') ?? '';
      _isCustomEndpoint =
          prefs.getBool('ollama_cloud_custom_endpoint') ?? false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ollama_cloud_api_key', _apiKeyController.text);
    await prefs.setString('ollama_cloud_endpoint', _endpointController.text);
    await prefs.setString(
      'ollama_cloud_organization',
      _organizationController.text,
    );
    await prefs.setBool('ollama_cloud_custom_endpoint', _isCustomEndpoint);
  }

  void _updateConfig() {
    setState(() {});
    _saveConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _endpointController.dispose();
    _organizationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Use Custom Endpoint'),
            subtitle: const Text('Otherwise use default Ollama Cloud endpoint'),
            value: _isCustomEndpoint,
            onChanged: (bool value) {
              setState(() {
                _isCustomEndpoint = value;
              });
              _saveConfig();
            },
          ),
          if (_isCustomEndpoint) ...[
            _buildTextField('Endpoint URL', _endpointController, (v) {
              setState(() {});
              _saveConfig();
            }),
          ],
          _buildTextField('API Key', _apiKeyController, (v) {
            setState(() {});
            _saveConfig();
          }, obscureText: true),
          _buildTextField('Organization (optional)', _organizationController, (
            v,
          ) {
            setState(() {});
            _saveConfig();
          }),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged, {
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
