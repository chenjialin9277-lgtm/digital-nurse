import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPasswordDialog extends StatefulWidget {
  const SettingsPasswordDialog({super.key, required this.verify});

  final bool Function(String value) verify;

  @override
  State<SettingsPasswordDialog> createState() => _SettingsPasswordDialogState();
}

class _SettingsPasswordDialogState extends State<SettingsPasswordDialog> {
  final _controller = TextEditingController();
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline, size: 38),
      title: const Text('输入设置密码'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _controller,
          autofocus: true,
          obscureText: _hide,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 12,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: '密码',
            errorText: _error,
            helperText: '如尚未修改，初始密码为 123456',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.password),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hide = !_hide),
              icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('进入设置')),
      ],
    );
  }

  void _submit() {
    if (widget.verify(_controller.text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = '密码不正确');
      _controller
        ..clear()
        ..selection = const TextSelection.collapsed(offset: 0);
    }
  }
}
