import 'package:flutter/material.dart';

import '../../../models/offline_speech_language.dart';
import '../models/education_language_content.dart';
import 'comprehension_question_editor.dart';

class LanguageContentEditor extends StatefulWidget {
  const LanguageContentEditor({
    super.key,
    required this.language,
    required this.initial,
  });

  final OfflineSpeechLanguage language;
  final EducationLanguageContent initial;

  @override
  State<LanguageContentEditor> createState() => LanguageContentEditorState();
}

class LanguageContentEditorState extends State<LanguageContentEditor> {
  final formKey = GlobalKey<FormState>();
  final questionKey = GlobalKey<ComprehensionQuestionEditorState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _summary;
  bool _dirty = false;

  bool get isDirty => _dirty;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial.title);
    _body = TextEditingController(text: widget.initial.body);
    _summary = TextEditingController(text: widget.initial.summary);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _summary.dispose();
    super.dispose();
  }

  bool validateForPublish() => formKey.currentState?.validate() ?? false;

  bool get hasAnyText =>
      _title.text.trim().isNotEmpty ||
      _body.text.trim().isNotEmpty ||
      _summary.text.trim().isNotEmpty ||
      (questionKey.currentState?.question.isNotEmpty ?? false);

  void replaceWith(EducationLanguageContent content) {
    _title.text = content.title;
    _body.text = content.body;
    _summary.text = content.summary;
    questionKey.currentState?.replaceWith(content);
    if (!_dirty) setState(() => _dirty = true);
  }

  EducationLanguageContent content({
    required bool published,
    required bool needsReview,
  }) {
    final question = questionKey.currentState;
    return EducationLanguageContent(
      title: _title.text.trim(),
      body: _body.text.trim(),
      summary: _summary.text.trim(),
      question: question?.question ?? widget.initial.question,
      options: question?.options ?? widget.initial.options,
      correctIndex: question?.correctIndex ?? widget.initial.correctIndex,
      explanation: question?.explanation ?? widget.initial.explanation,
      published: published,
      needsReview: needsReview,
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language.name;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: Key('education-title-$language'),
            controller: _title,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: '宣教名称（${widget.language.editorLabel}）',
              border: const OutlineInputBorder(),
            ),
            validator: (value) => _required(value, 40, '宣教名称'),
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: Key('education-body-$language'),
            controller: _body,
            minLines: 4,
            maxLines: 8,
            maxLength: 1200,
            decoration: const InputDecoration(
              labelText: '宣教正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (value) => _required(value, 1200, '宣教正文'),
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: Key('education-summary-$language'),
            controller: _summary,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: '简短摘要（可选）',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              return text.length > 120 ? '摘要不能超过120个字符' : null;
            },
            onChanged: (_) => _markDirty(),
          ),
          ComprehensionQuestionEditor(
            key: questionKey,
            language: widget.language,
            initial: widget.initial,
            onChanged: _markDirty,
          ),
        ],
      ),
    );
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  String? _required(String? value, int max, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '请填写$label';
    return text.length > max ? '$label不能超过$max个字符' : null;
  }
}
