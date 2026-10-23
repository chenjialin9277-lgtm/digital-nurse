import 'dart:convert';

import '../models/education_language_content.dart';

typedef EducationTranslationCallback =
    Future<EducationTranslationBundle> Function(
      EducationLanguageContent mandarin,
    );

class EducationTranslationBundle {
  const EducationTranslationBundle({
    required this.cantonese,
    required this.english,
  });

  final EducationLanguageContent cantonese;
  final EducationLanguageContent english;
}

/// Uses the department's connected Xiaozhi assistant to create translation
/// drafts. Generated medical education is intentionally never auto-published.
class EducationTranslationService {
  const EducationTranslationService({required this.requestText});

  final Future<String> Function(String prompt) requestText;

  Future<EducationTranslationBundle> translateFromMandarin(
    EducationLanguageContent source,
  ) async {
    if (!source.isComplete) {
      throw StateError('请先完整填写并检查普通话宣教及理解题');
    }
    final sourceJson = jsonEncode(<String, Object?>{
      'title': source.title,
      'body': source.body,
      'summary': source.summary,
      'question': source.question,
      'options': source.options,
      'correctIndex': source.correctIndex,
      'explanation': source.explanation,
    });
    final response = await requestText('''
你是医院宣教翻译助手。请把下面的普通话书面宣教准确翻译成两套内容：
1. cantonese：自然、易懂的粤语书面表达；医学事实、数字、剂量、时间和警示不得改变。
2. english：清晰、通俗、专业的英文；医学事实、数字、剂量、时间和警示不得改变。

必须只返回一个合法 JSON 对象，不要使用 Markdown，不要解释。结构必须严格为：
{"cantonese":{"title":"","body":"","summary":"","question":"","options":["",""],"correctIndex":0,"explanation":""},"english":{"title":"","body":"","summary":"","question":"","options":["",""],"correctIndex":0,"explanation":""}}
两种语言的 options 数量和 correctIndex 必须与原文完全一致。原文 JSON：
$sourceJson
''');
    final decoded = _decodeObject(response);
    return EducationTranslationBundle(
      cantonese: _content(decoded['cantonese'], source, '粤语'),
      english: _content(decoded['english'], source, '英语'),
    );
  }

  Map<String, dynamic> _decodeObject(String response) {
    final first = response.indexOf('{');
    final last = response.lastIndexOf('}');
    if (first < 0 || last <= first) throw const FormatException('未收到有效翻译');
    final value = jsonDecode(response.substring(first, last + 1));
    if (value is! Map) throw const FormatException('翻译格式不正确');
    return Map<String, dynamic>.from(value);
  }

  EducationLanguageContent _content(
    Object? value,
    EducationLanguageContent source,
    String label,
  ) {
    if (value is! Map) throw FormatException('$label翻译缺失');
    final map = Map<String, dynamic>.from(value);
    final options = (map['options'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item.toString().trim())
        .toList(growable: false);
    final correctIndex = (map['correctIndex'] as num?)?.toInt();
    final content = EducationLanguageContent(
      title: map['title']?.toString().trim() ?? '',
      body: map['body']?.toString().trim() ?? '',
      summary: map['summary']?.toString().trim() ?? '',
      question: map['question']?.toString().trim() ?? '',
      options: options,
      correctIndex: correctIndex ?? -1,
      explanation: map['explanation']?.toString().trim() ?? '',
      published: false,
      needsReview: true,
    );
    if (!content.isComplete ||
        options.length != source.options.length ||
        content.correctIndex != source.correctIndex) {
      throw FormatException('$label翻译不完整，请重新生成');
    }
    return content;
  }
}
