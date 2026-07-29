import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneServerGroqConfig extends StatefulWidget {
  const PhoneServerGroqConfig({super.key});

  @override
  State<PhoneServerGroqConfig> createState() => _PhoneServerGroqConfigState();
}

class _PhoneServerGroqConfigState extends State<PhoneServerGroqConfig> {
  late TextEditingController _apiKeyController;
  final List<String> _availableModels = [
    'llama3-8b-8192',
    'llama3-70b-8192',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  ];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('groq_api_key') ?? '';
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groq_api_key', _apiKeyController.text);
  }

  void _updateConfig() {
    setState(() {});
    _saveConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available Models: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ..._availableModels.map(
                  (model) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Text(model, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
