import 'package:flutter/material.dart';

import '../../../models/offline_speech_language.dart';
import '../models/education_language_content.dart';

class ComprehensionQuestionEditor extends StatefulWidget {
  const ComprehensionQuestionEditor({
    super.key,
    required this.language,
    required this.initial,
    required this.onChanged,
  });

  final OfflineSpeechLanguage language;
  final EducationLanguageContent initial;
  final VoidCallback onChanged;

  @override
  State<ComprehensionQuestionEditor> createState() =>
      ComprehensionQuestionEditorState();
}

class ComprehensionQuestionEditorState
    extends State<ComprehensionQuestionEditor> {
  late final TextEditingController _question;
  late final TextEditingController _explanation;
  late final List<TextEditingController> _options;
  late int _correctIndex;

  @override
  void initState() {
    super.initState();
    _question = TextEditingController(text: widget.initial.question);
    _explanation = TextEditingController(text: widget.initial.explanation);
    _options =
        (widget.initial.options.isEmpty
                ? const ['', '']
                : widget.initial.options)
            .map((text) => TextEditingController(text: text))
            .toList();
    while (_options.length < 2) {
      _options.add(TextEditingController());
    }
    _correctIndex = widget.initial.correctIndex.clamp(0, _options.length - 1);
  }

  @override
  void dispose() {
    _question.dispose();
    _explanation.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  String get question => _question.text.trim();
  String get explanation => _explanation.text.trim();
  List<String> get options => _options.map((item) => item.text.trim()).toList();
  int get correctIndex => _correctIndex;

  @override
  Widget build(BuildContext context) {
    final language = widget.language.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 30),
        Text(
          '理解确认题',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: Key('education-question-$language'),
          controller: _question,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: '问题',
            border: OutlineInputBorder(),
          ),
          validator: (value) => _requiredLength(value, 120, '问题'),
          onChanged: (_) => widget.onChanged(),
        ),
        RadioGroup<int>(
          groupValue: _correctIndex,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _correctIndex = value);
            widget.onChanged();
          },
          child: Column(
            children: List.generate(_options.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<int>(value: index),
                    Expanded(
                      child: TextFormField(
                        key: Key('education-option-$language-$index'),
                        controller: _options[index],
                        maxLength: 80,
                        decoration: InputDecoration(
                          labelText:
                              '选项 ${index + 1}${index == _correctIndex ? '（正确答案）' : ''}',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => _requiredLength(value, 80, '选项'),
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        tooltip: '删除选项',
                        onPressed: () => _removeOption(index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
        if (_options.length < 4)
          TextButton.icon(
            onPressed: _addOption,
            icon: const Icon(Icons.add),
            label: const Text('添加选项'),
          ),
        const SizedBox(height: 8),
        TextFormField(
          key: Key('education-explanation-$language'),
          controller: _explanation,
          minLines: 2,
          maxLines: 4,
          maxLength: 240,
          decoration: const InputDecoration(
            labelText: '答案解释',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          validator: (value) => _requiredLength(value, 240, '答案解释'),
          onChanged: (_) => widget.onChanged(),
        ),
      ],
    );
  }

  void _addOption() {
    if (_options.length >= 4) return;
    setState(() => _options.add(TextEditingController()));
    widget.onChanged();
  }

  void _removeOption(int index) {
    if (_options.length <= 2) return;
    setState(() {
      _options.removeAt(index).dispose();
      if (_correctIndex == index) _correctIndex = 0;
      if (_correctIndex > index) _correctIndex -= 1;
    });
    widget.onChanged();
  }

  String? _requiredLength(String? value, int max, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '请填写$label';
    if (text.length > max) return '$label不能超过$max个字符';
    if (label == '选项') {
      final values = options.where((item) => item.isNotEmpty).toList();
      if (values.toSet().length != values.length) return '选项内容不能重复';
    }
    return null;
  }
}
