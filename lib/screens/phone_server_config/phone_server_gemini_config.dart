import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneServerGeminiConfig extends StatefulWidget {
  const PhoneServerGeminiConfig({super.key});

  @override
  State<PhoneServerGeminiConfig> createState() =>
      _PhoneServerGeminiConfigState();
}

class _PhoneServerGeminiConfigState extends State<PhoneServerGeminiConfig> {
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  final List<String> _availableModels = [
    'gemini-1.5-pro-latest',
    'gemini-1.5-flash-latest',
    'gemini-2.0-flash',
    'gemini-2.0-pro',
  ];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController(text: 'gemini-1.5-pro-latest');
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _modelController.text =
          prefs.getString('gemini_model') ?? 'gemini-1.5-pro-latest';
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text);
    await prefs.setString('gemini_model', _modelController.text);
  }

  void _updateConfig() {
    setState(() {});
    _saveConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('API Key', _apiKeyController, (v) {
            setState(() {});
            _saveConfig();
          }, obscureText: true),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _modelController.text,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: _availableModels.map((model) {
              return DropdownMenuItem<String>(value: model, child: Text(model));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _modelController.text = value;
                });
                _saveConfig();
              }
            },
          ),
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
