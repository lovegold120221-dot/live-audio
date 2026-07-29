import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneServerOpencodeConfig extends StatefulWidget {
  const PhoneServerOpencodeConfig({super.key});

  @override
  State<PhoneServerOpencodeConfig> createState() =>
      _PhoneServerOpencodeConfigState();
}

class _PhoneServerOpencodeConfigState extends State<PhoneServerOpencodeConfig> {
  late TextEditingController _configPathController;
  late TextEditingController _modelController;
  bool _enableRemoteServer = false;

  @override
  void initState() {
    super.initState();
    _configPathController = TextEditingController(
      text: '~/.opencode/config.json',
    );
    _modelController = TextEditingController(text: 'llama3.2');
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _configPathController.text =
          prefs.getString('opencode_config_path') ?? '~/.opencode/config.json';
      _modelController.text = prefs.getString('opencode_model') ?? 'llama3.2';
      _enableRemoteServer = prefs.getBool('opencode_remote_server') ?? false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('opencode_config_path', _configPathController.text);
    await prefs.setString('opencode_model', _modelController.text);
    await prefs.setBool('opencode_remote_server', _enableRemoteServer);
  }

  void _updateConfig() {
    setState(() {});
    _saveConfig();
  }

  @override
  void dispose() {
    _configPathController.dispose();
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
          SwitchListTile(
            title: const Text('Enable Remote Server'),
            subtitle: const Text('Connect to opencode server instead of CLI'),
            value: _enableRemoteServer,
            onChanged: (bool value) {
              setState(() {
                _enableRemoteServer = value;
              });
              _saveConfig();
            },
          ),
          _buildTextField('Config Path', _configPathController, (v) {
            setState(() {});
            _saveConfig();
          }),
          _buildTextField('Model Name', _modelController, (v) {
            setState(() {});
            _saveConfig();
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Opencode CLI Setup:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Install opencode on your system',
                  style: TextStyle(fontSize: 12),
                ),
                const Text(
                  '2. Run: opencode serve --port 4096',
                  style: TextStyle(fontSize: 12),
                ),
                const Text(
                  '3. Configure this app with the server endpoint',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The server must be running on localhost:4096',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber,
                    fontWeight: FontWeight.w600,
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
