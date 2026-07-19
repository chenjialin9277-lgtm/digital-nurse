import 'package:digital_nurse/features/education/models/comprehension_result.dart';
import 'package:digital_nurse/features/education/models/education_item.dart';
import 'package:digital_nurse/features/education/models/education_language_content.dart';
import 'package:digital_nurse/models/offline_speech_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('宣教项目可完整保存并恢复三语内容和理解题', () {
    final item = EducationItem(
      id: 'admission',
      category: '入院宣教',
      contents: {
        OfflineSpeechLanguage.mandarin: const EducationLanguageContent(
          title: '入院注意事项',
          body: '请配合护士完成身份核对。',
          summary: '配合身份核对',
          question: '办理入院后应该怎么做？',
          options: ['配合护士核对身份', '自行离开病区'],
          correctIndex: 0,
          explanation: '应配合护士完成身份核对。',
          published: true,
          needsReview: false,
        ),
      },
      estimatedManualMinutes: 3,
      sortOrder: 0,
      favorite: true,
      enabled: true,
      version: 1,
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );

    final restored = EducationItem.fromJson(item.toJson());

    expect(restored, item);
    expect(restored.isAvailableIn(OfflineSpeechLanguage.mandarin), isTrue);
    expect(restored.isAvailableIn(OfflineSpeechLanguage.cantonese), isFalse);
  });

  test('未发布或不完整的语言不会提供给患者', () {
    const draft = EducationLanguageContent(
      title: 'Discharge',
      body: 'Follow the nurse instructions.',
      summary: '',
      question: '',
      options: [],
      correctIndex: -1,
      explanation: '',
      published: false,
      needsReview: true,
    );
    final item = EducationItem(
      id: 'discharge',
      category: '出院宣教',
      contents: const {OfflineSpeechLanguage.english: draft},
      estimatedManualMinutes: 2,
      sortOrder: 0,
      favorite: false,
      enabled: true,
      version: 1,
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );

    expect(item.isAvailableIn(OfflineSpeechLanguage.english), isFalse);
  });

  test('理解确认结果不包含患者身份字段', () {
    final result = ComprehensionResult(
      itemId: 'admission',
      itemVersion: 1,
      language: OfflineSpeechLanguage.mandarin,
      selectedIndex: 0,
      correctIndex: 0,
      attempt: 1,
    );

    expect(result.isCorrect, isTrue);
    expect(result.toJson().keys, isNot(contains('patientName')));
    expect(result.toJson().keys, isNot(contains('hospitalNumber')));
    expect(result.toJson().keys, isNot(contains('bedNumber')));
  });
}
