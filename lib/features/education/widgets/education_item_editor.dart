import 'package:flutter/material.dart';

import '../../../models/offline_speech_language.dart';
import '../models/education_item.dart';
import '../models/education_language_content.dart';
import 'language_content_editor.dart';

class EducationItemEditor extends StatefulWidget {
  const EducationItemEditor({super.key, this.initial, required this.sortOrder});

  final EducationItem? initial;
  final int sortOrder;

  @override
  State<EducationItemEditor> createState() => _EducationItemEditorState();
}

class _EducationItemEditorState extends State<EducationItemEditor> {
  final _metaFormKey = GlobalKey<FormState>();
  final _editorKeys = {
    for (final language in OfflineSpeechLanguage.values)
      language: GlobalKey<LanguageContentEditorState>(),
  };
  late final TextEditingController _category;
  late final TextEditingController _minutes;
  OfflineSpeechLanguage _language = OfflineSpeechLanguage.mandarin;

  @override
  void initState() {
    super.initState();
    _category = TextEditingController(text: widget.initial?.category ?? '科室宣教');
    _minutes = TextEditingController(
      text: (widget.initial?.estimatedManualMinutes ?? 3).toString(),
    );
  }

  @override
  void dispose() {
    _category.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增宣教' : '编辑宣教'),
      content: SizedBox(
        width: 820,
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Form(
              key: _metaFormKey,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _category,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: '分类',
                        border: OutlineInputBorder(),
                      ),
                      validator:
                          (value) =>
                              (value?.trim().isEmpty ?? true) ? '请填写分类' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: TextFormField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '预计节省时间（分钟）',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final number = int.tryParse(value?.trim() ?? '');
                        return number == null || number < 1 || number > 30
                            ? '请填写1～30'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<OfflineSpeechLanguage>(
              showSelectedIcon: false,
              segments:
                  OfflineSpeechLanguage.values
                      .map(
                        (language) => ButtonSegment(
                          value: language,
                          label: Text(language.label),
                        ),
                      )
                      .toList(),
              selected: {_language},
              onSelectionChanged:
                  (value) => setState(() => _language = value.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: IndexedStack(
                  index: OfflineSpeechLanguage.values.indexOf(_language),
                  children:
                      OfflineSpeechLanguage.values.map((language) {
                        return LanguageContentEditor(
                          key: _editorKeys[language],
                          language: language,
                          initial:
                              widget.initial?.contentFor(language) ??
                              _emptyContent,
                        );
                      }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _saveDraft, child: const Text('保存草稿')),
        FilledButton(
          onPressed: _publishCurrentLanguage,
          child: Text('保存并发布${_language.label}'),
        ),
      ],
    );
  }

  void _saveDraft() {
    if (!(_metaFormKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _buildItem());
  }

  void _publishCurrentLanguage() {
    final metaValid = _metaFormKey.currentState?.validate() ?? false;
    final contentValid =
        _editorKeys[_language]?.currentState?.validateForPublish() ?? false;
    if (!metaValid || !contentValid) return;
    Navigator.pop(context, _buildItem(publishLanguage: _language));
  }

  EducationItem _buildItem({OfflineSpeechLanguage? publishLanguage}) {
    final initial = widget.initial;
    final now = DateTime.now().toUtc();
    final contents = <OfflineSpeechLanguage, EducationLanguageContent>{};
    for (final language in OfflineSpeechLanguage.values) {
      final editor = _editorKeys[language]!.currentState!;
      final old = initial?.contentFor(language) ?? _emptyContent;
      final publishing = publishLanguage == language;
      final changed = editor.isDirty;
      contents[language] = editor.content(
        published: publishing ? true : (changed ? false : old.published),
        needsReview: publishing ? false : (changed ? true : old.needsReview),
      );
    }
    return EducationItem(
      id: initial?.id ?? 'education_${now.microsecondsSinceEpoch}',
      category: _category.text.trim(),
      contents: contents,
      estimatedManualMinutes: int.parse(_minutes.text.trim()),
      sortOrder: initial?.sortOrder ?? widget.sortOrder,
      favorite: initial?.favorite ?? false,
      enabled: initial?.enabled ?? true,
      version: (initial?.version ?? 0) + 1,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
    );
  }

  static const _emptyContent = EducationLanguageContent(
    title: '',
    body: '',
    summary: '',
    question: '',
    options: ['', ''],
    correctIndex: 0,
    explanation: '',
    published: false,
    needsReview: true,
  );
}
